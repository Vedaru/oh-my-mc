import 'dart:convert';
import 'dart:io';

import '../net/downloader.dart';
import '../net/progress.dart';
import 'asset_index.dart';
import 'host.dart';
import 'library_graph.dart';
import 'version_json.dart';

/// Directory layout for one install root. Kept in one place because every path
/// bug in a launcher traces back to two modules disagreeing about this.
class GamePaths {
  const GamePaths(this.root);

  /// The `.minecraft`-equivalent directory.
  final String root;

  String get versions => '$root/versions';
  String get libraries => '$root/libraries';
  String get assets => '$root/assets';
  String get assetIndexes => '$assets/indexes';
  String get assetObjects => '$assets/objects';
  String get virtualAssets => '$assets/virtual';
  String get legacyResources => '$root/resources';
  String get loggingConfigs => '$assets/log_configs';

  String versionDir(String id) => '$versions/$id';
  String versionJson(String id) => '$versions/$id/$id.json';
  String versionJar(String id) => '$versions/$id/$id.jar';
  String natives(String id) => '$versions/$id/natives';
  String assetIndexFile(String indexId) => '$assetIndexes/$indexId.json';

  /// Maven-relative library path under `libraries/`.
  String libraryFile(String mavenPath) => '$libraries/$mavenPath';

  /// Hashed object path under `assets/objects/`.
  String assetObject(String hash) =>
      '$assetObjects/${hash.substring(0, 2)}/$hash';

  /// `/mnt/games/mc` → `/mnt/games/mc`, but Windows paths keep backslashes out
  /// of URLs. Only used for logging, so no normalisation is attempted.
  static String display(String path) => path.replaceAll('\\', '/');
}

/// One install stage, so the UI can show meaningful progress rather than a
/// single anonymous bar.
enum InstallStage { manifest, versionJson, libraries, natives, assets, logging }

/// A complete, verified list of work for installing [versionId].
///
/// This is a *plan*: it touches no files. The downloader executes it. Keeping
/// planning pure means we can assert the exact file set in tests.
class InstallPlan {
  const InstallPlan({
    required this.versionId,
    required this.paths,
    required this.tasks,
    required this.totalBytes,
    required this.stages,
    required this.missingNatives,
  });

  final String versionId;
  final GamePaths paths;
  final List<DownloadTask> tasks;
  final int totalBytes;

  /// Bytes to fetch per stage, for per-stage progress bars.
  final Map<InstallStage, int> stages;

  /// Non-empty when some library declares natives but none resolve for this
  /// host — a hard incompatibility, reported before downloading anything.
  final List<String> missingNatives;

  int get fileCount => tasks.length;

  bool get isEmpty => tasks.isEmpty;
}

/// Builds the plan for one version.
///
/// [features] mirrors the game-side flags; it affects which argument and
/// library entries exist, so it must be passed for the plan to match the launch.
InstallPlan planInstall({
  required VersionJson version,
  required RuleContext host,
  required GamePaths paths,
  Map<String, bool> features = const {},
  AssetIndex? assetIndex,
  bool includeAssets = true,
}) {
  final tasks = <DownloadTask>[];
  final stages = <InstallStage, int>{};
  var missingNatives = <String>[];

  void add(
    InstallStage stage,
    String path,
    String url,
    String sha1,
    int size, {
    DownloadPriority priority = DownloadPriority.library,
  }) {
    if (url.isEmpty || path.isEmpty) return;
    tasks.add(
      DownloadTask(
        url: Uri.parse(url),
        targetPath: path,
        sha1: sha1,
        size: size,
        priority: priority,
      ),
    );
    stages[stage] = (stages[stage] ?? 0) + size;
  }

  // 1. Client jar. Forge/Fabric override `jar`, so honour it.
  final client = version.downloads['client'];
  if (client != null) {
    add(
      InstallStage.versionJson,
      paths.versionJar(version.jar ?? version.id),
      client.url,
      client.sha1,
      client.size,
      priority: DownloadPriority.metadata,
    );
  }

  // 2. Libraries and natives for this host.
  final graph = buildLibraryGraph(version, host, features: features);
  for (final jar in graph.jars) {
    add(
      InstallStage.libraries,
      paths.libraryFile(jar.path),
      jar.url,
      jar.sha1,
      jar.size,
    );
  }
  if (graph.natives.isNotEmpty) {
    stages.putIfAbsent(InstallStage.natives, () => 0);
  }
  final declaredNatives = version.libraries.where(
    (l) => l.natives != null && l.natives!.isNotEmpty,
  );
  if (declaredNatives.isNotEmpty && graph.natives.isEmpty) {
    missingNatives = [for (final l in declaredNatives) l.name];
  }

  // 3. Asset index file, then the objects it references.
  if (includeAssets && version.assetIndexName.isNotEmpty) {
    final indexTarget = paths.assetIndexFile(version.assetIndexName);
    final indexMeta = version.assetIndex;
    if (indexMeta != null) {
      add(
        InstallStage.assets,
        indexTarget,
        indexMeta.url,
        indexMeta.sha1,
        indexMeta.size,
        priority: DownloadPriority.metadata,
      );
    }
    if (assetIndex != null) {
      // Distinct blobs only: many logical names share one hash.
      for (final blob in assetIndex.distinctBlobs.values) {
        add(
          InstallStage.assets,
          paths.assetObject(blob.hash),
          blob.url,
          blob.hash,
          blob.size,
          priority: DownloadPriority.asset,
        );
      }
    }
  }

  // 4. Logging configuration (log4j2 xml), for versions that ask for one.
  final logging = version.raw['logging'];
  if (logging is Map && logging['client'] is Map) {
    final clientLog = logging['client'] as Map;
    final file = clientLog['file'];
    if (file is Map) {
      add(
        InstallStage.logging,
        '${paths.loggingConfigs}/${file['id'] ?? 'client.xml'}',
        '${file['url'] ?? ''}',
        '${file['sha1'] ?? ''}',
        (file['size'] as num?)?.toInt() ?? 0,
        priority: DownloadPriority.metadata,
      );
    }
  }

  return InstallPlan(
    versionId: version.id,
    paths: paths,
    tasks: tasks,
    totalBytes: tasks.fold(0, (s, t) => s + t.size),
    stages: stages,
    missingNatives: missingNatives,
  );
}

/// Files that must exist for a launch, independent of downloading.
///
/// Checked right before spawning the JVM so a partial install produces
/// "3 files missing" instead of a cryptic Java error.
List<String> missingLaunchFiles({
  required VersionJson version,
  required List<String> classpath,
  required GamePaths paths,
  required bool Function(String path) exists,
}) {
  final missing = <String>[];
  final jar = paths.versionJar(version.jar ?? version.id);
  if (!exists(jar)) missing.add(jar);
  for (final f in classpath) {
    if (!exists(f)) missing.add(f);
  }
  return missing;
}

/// Builds a resolver callback backed by the versions directory, for
/// `inheritsFrom`.
///
/// Returns `null` for a missing parent so the resolver raises its explicit
/// "parent not installed" error rather than silently merging nothing.
VersionJson? Function(String id) directoryResolver(GamePaths paths) {
  return (id) {
    final file = File(paths.versionJson(id));
    if (!file.existsSync()) return null;
    return VersionJson.fromJson(
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
    );
  };
}

/// Human-readable summary, for logs and the install confirmation sheet.
String describeInstall(InstallPlan plan) {
  final parts = ['${plan.fileCount} files', formatBytes(plan.totalBytes)];
  for (final entry in plan.stages.entries) {
    parts.add('${entry.key.name}: ${formatBytes(entry.value)}');
  }
  return parts.join(', ');
}
