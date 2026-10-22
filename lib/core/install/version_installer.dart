import 'dart:convert';
import 'dart:io';

import '../mc/asset_index.dart';
import '../mc/host.dart';
import '../mc/install_plan.dart';
import '../mc/library_graph.dart';
import '../mc/version_json.dart';
import '../mc/version_resolver.dart';
import '../net/cancellation.dart';
import '../net/downloader.dart';
import '../net/mirror.dart';
import '../net/progress.dart';
import '../net/version_manifest.dart';
import 'asset_layout.dart';
import 'extract.dart';
import 'verify.dart';

/// The step an install has reached. Ordered, so the UI can show "step 3 of 6"
/// without inventing its own list.
enum InstallPhase {
  manifest,
  versionJson,
  parents,
  assetIndex,
  planning,
  download,
  natives,
  assets,
  verify,
}

/// A progress sample. [download] is only present during [InstallPhase.download];
/// other phases report a [detail] string instead, because "unpacking natives"
/// has no byte counter and pretending it does produces a bar that sits at 0%.
class InstallProgress {
  const InstallProgress({
    required this.phase,
    this.download,
    this.detail,
    this.step = 0,
    this.steps = 0,
  });

  final InstallPhase phase;
  final DownloadProgress? download;
  final String? detail;
  final int step;
  final int steps;

  @override
  String toString() =>
      '${phase.name}${detail == null ? '' : ' ($detail)'}'
      '${download == null ? '' : ' ${download!}'}';
}

/// Everything an install produced, for the caller to log or show.
class InstallResult {
  const InstallResult({
    required this.versionId,
    required this.plan,
    required this.version,
    required this.natives,
    required this.assets,
    required this.verification,
  });

  final String versionId;
  final InstallPlan plan;
  final VersionJson version;
  final List<ExtractResult> natives;
  final AssetMaterialization assets;
  final VerifyReport verification;

  int get nativesFiles => natives.fold(0, (sum, r) => sum + r.entries.length);
}

/// Runs the whole install for one version.
///
/// The pipeline is deliberately explicit rather than a chain of callbacks: the
/// ordering constraints are the interesting part, and they are documented at
/// each await.
class VersionInstaller {
  VersionInstaller({
    HttpClient? client,
    MirrorChain? mirrors,
    FileDownloader? downloader,
    VersionManifestService? manifestService,
    this.concurrency = 8,
  }) : _client = client ?? HttpClient(),
       mirrors = mirrors ?? MirrorChain(),
       _downloader =
           downloader ?? FileDownloader(client: client, mirrors: mirrors),
       _manifest = manifestService;

  final HttpClient _client;
  final MirrorChain mirrors;
  final FileDownloader _downloader;
  VersionManifestService? _manifest;

  /// Parallel transfers. Higher is better for the ~3000-asset case and worse for
  /// a metered connection; 8 is what every launcher converges on.
  final int concurrency;

  /// Installs [versionId] into [paths].
  ///
  /// Throws [CancelledException] when [cancel] fires, a [DownloadFailedException]
  /// when a file cannot be fetched, and [StateError] for metadata that cannot be
  /// resolved (missing parent, no manifest entry). On any failure the partial
  /// tree is left in place on purpose — the next attempt resumes from it.
  Future<InstallResult> install({
    required String versionId,
    required GamePaths paths,
    required RuleContext host,
    Map<String, bool> features = const {},
    bool includeAssets = true,
    String assetBaseUrl = defaultAssetBaseUrl,
    CancelToken? cancel,
    void Function(InstallProgress)? onProgress,
  }) async {
    final steps = 9;

    void phase(
      InstallPhase p, {
      String? detail,
      int step = 0,
      DownloadProgress? download,
    }) {
      onProgress?.call(
        InstallProgress(
          phase: p,
          detail: detail,
          step: step,
          steps: steps,
          download: download,
        ),
      );
    }

    phase(InstallPhase.manifest, step: 1);
    final manifest = await _loadManifest(paths, cancel);

    phase(InstallPhase.versionJson, step: 2, detail: versionId);
    final root = await _loadOrFetchVersion(
      versionId,
      manifest,
      paths,
      cancel: cancel,
    );

    // Parents must exist on disk before `resolveInheritance`, because
    // `directoryResolver` reads them from there — the same path a later launch
    // and `verifyInstall` use, so a parent is fetched exactly once.
    phase(InstallPhase.parents, step: 3, detail: versionId);
    final version = await _resolveChain(root, manifest, paths, cancel: cancel);

    // The index has to be parsed before planning: `planInstall` emits one task
    // per distinct blob, which it can only know from the parsed index.
    AssetIndex? assetIndex;
    if (includeAssets && version.assetIndexName.isNotEmpty) {
      phase(InstallPhase.assetIndex, step: 4, detail: version.assetIndexName);
      assetIndex = await _loadOrFetchAssetIndex(version, paths, cancel: cancel);
    }

    phase(InstallPhase.planning, step: 5);
    final plan = planInstall(
      version: version,
      host: host,
      paths: paths,
      features: features,
      assetIndex: assetIndex,
      includeAssets: includeAssets,
      assetBaseUrl: assetBaseUrl,
    );

    if (plan.missingNatives.isNotEmpty) {
      throw StateError(
        'no natives resolve for this platform: '
        '${plan.missingNatives.join(', ')}',
      );
    }

    phase(InstallPhase.download, step: 6);
    await for (final progress in _downloader.download(
      plan.tasks,
      concurrency: concurrency,
      cancel: cancel,
    )) {
      phase(InstallPhase.download, step: 6, download: progress);
    }
    cancel?.throwIfCancelled('download');

    phase(InstallPhase.natives, step: 7);
    final natives = await extractNatives(
      archives: _nativeSpecs(version, host, paths, features),
      destination: paths.natives(version.id),
      cancel: cancel,
    );

    phase(InstallPhase.assets, step: 8);
    final assets = assetIndex == null || !includeAssets
        ? AssetMaterialization.none
        : await materializeAssets(
            index: assetIndex,
            paths: paths,
            indexId: version.assetIndexName,
            cancel: cancel,
          );

    phase(InstallPhase.verify, step: 9);
    final verification = await verifyInstall(plan);

    return InstallResult(
      versionId: versionId,
      plan: plan,
      version: version,
      natives: natives,
      assets: assets,
      verification: verification,
    );
  }

  /// The archives to unpack, resolved for this host.
  ///
  /// Rebuilt from the version rather than threaded out of `planInstall`, because
  /// the plan only carries download tasks — it drops which archive belongs to
  /// which library, and the `extract.exclude` list comes with that library.
  List<NativeArchiveSpec> _nativeSpecs(
    VersionJson version,
    RuleContext host,
    GamePaths paths,
    Map<String, bool> features,
  ) {
    final graph = buildLibraryGraph(version, host, features: features);
    return [
      for (final NativeArchive archive in graph.natives)
        NativeArchiveSpec(
          file: paths.libraryFile(archive.file.path),
          label: archive.file.path,
          exclude: archive.exclude,
        ),
    ];
  }

  Future<VersionManifest> _loadManifest(
    GamePaths paths,
    CancelToken? cancel,
  ) async {
    final service =
        _manifest ??
        VersionManifestService(
          cacheFile: File('${paths.root}/version_manifest_v2.json'),
          client: _client,
          mirrors: mirrors,
        );
    _manifest = service;
    cancel?.throwIfCancelled('manifest');
    return service.load();
  }

  /// Reads the version JSON from disk, or fetches it from the manifest entry.
  ///
  /// A file already on disk wins: it may have been written by a modloader
  /// installer (Forge writes its own profile), and re-fetching would overwrite
  /// the patched metadata with vanilla.
  Future<VersionJson> _loadOrFetchVersion(
    String id,
    VersionManifest manifest,
    GamePaths paths, {
    CancelToken? cancel,
    bool overwrite = false,
  }) async {
    final file = File(paths.versionJson(id));
    if (!overwrite && file.existsSync()) {
      try {
        return VersionJson.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>,
        );
      } on FormatException {
        // Corrupt: fall through and re-fetch rather than failing the install.
      }
    }

    final entry = manifest.byId(id);
    if (entry == null) {
      throw StateError(
        'version "$id" is not in the manifest and no local metadata exists',
      );
    }

    await _fetchOne(
      url: entry.url,
      target: paths.versionJson(id),
      sha1: entry.sha1,
      cancel: cancel,
      priority: DownloadPriority.metadata,
    );

    final body = await file.readAsString();
    return VersionJson.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// Walks `inheritsFrom`, fetching any parent that is not on disk.
  Future<VersionJson> _resolveChain(
    VersionJson root,
    VersionManifest manifest,
    GamePaths paths, {
    CancelToken? cancel,
  }) async {
    if (root.inheritsFrom == null) return root;

    final seen = <String>{root.id};
    var current = root;
    while (current.inheritsFrom != null) {
      cancel?.throwIfCancelled('parents');
      final parentId = current.inheritsFrom!;
      if (!seen.add(parentId)) {
        throw StateError(
          'inheritance cycle at $parentId (${seen.join(' -> ')})',
        );
      }
      final parentFile = File(paths.versionJson(parentId));
      if (!parentFile.existsSync()) {
        await _loadOrFetchVersion(parentId, manifest, paths, cancel: cancel);
      }
      current = VersionJson.fromJson(
        jsonDecode(await parentFile.readAsString()) as Map<String, dynamic>,
      );
    }

    return resolveInheritance(root, (id) {
      final f = File(paths.versionJson(id));
      if (!f.existsSync()) return null;
      return VersionJson.fromJson(
        jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
      );
    });
  }

  /// Loads the parsed asset index, fetching it if absent.
  Future<AssetIndex> _loadOrFetchAssetIndex(
    VersionJson version,
    GamePaths paths, {
    CancelToken? cancel,
  }) async {
    final ref = version.assetIndex;
    final id = version.assetIndexName;
    final file = File(paths.assetIndexFile(id));

    // Only trust the on-disk copy when the metadata declares no hash to check;
    // otherwise a partial write would silently become the install's asset list.
    if (file.existsSync() && (ref == null || ref.sha1.isEmpty)) {
      return AssetIndex.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    }

    if (file.existsSync() && ref != null) {
      final ok = verifyInstall(
        InstallPlan(
          versionId: version.id,
          paths: paths,
          tasks: [
            DownloadTask(
              url: Uri.parse(ref.url),
              targetPath: file.path,
              sha1: ref.sha1,
              size: ref.size,
            ),
          ],
          totalBytes: ref.size,
          stages: const {},
          missingNatives: const [],
        ),
        checkHashes: true,
      );
      if ((await ok).isComplete) {
        return AssetIndex.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>,
        );
      }
    }

    if (ref == null || ref.url.isEmpty) {
      throw StateError(
        'version ${version.id} declares asset index "$id" but no download URL',
      );
    }

    await _fetchOne(
      url: ref.url,
      target: file.path,
      sha1: ref.sha1,
      size: ref.size,
      cancel: cancel,
      priority: DownloadPriority.metadata,
    );
    return AssetIndex.fromJson(
      jsonDecode(await file.readAsString()) as Map<String, dynamic>,
    );
  }

  Future<void> _fetchOne({
    required String url,
    required String target,
    required String sha1,
    int size = 0,
    CancelToken? cancel,
    DownloadPriority priority = DownloadPriority.metadata,
  }) async {
    await _downloader
        .download(
          [
            DownloadTask(
              url: Uri.parse(url),
              targetPath: target,
              sha1: sha1,
              size: size,
              priority: priority,
            ),
          ],
          concurrency: 1,
          cancel: cancel,
        )
        .drain<void>();
  }

  void close() {
    _downloader.close();
    _manifest?.close();
    _client.close(force: true);
  }
}
