import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../install/extract.dart' show safeRelativeEntryName;
import '../net/cancellation.dart';
import '../net/downloader.dart';
import '../net/mirror.dart';
import '../net/progress.dart';
import 'host.dart';
import 'java_catalog.dart';
import 'java_lzma.dart';

/// The step a runtime install has reached.
enum JavaProvisionPhase {
  catalog,
  manifest,
  download,
  extract,
  links,

  /// Probing the extracted `java` so a broken download is caught here, not at
  /// the first launch.
  verify,
}

class JavaProvisionProgress {
  const JavaProvisionProgress({
    required this.phase,
    this.download,
    this.detail,
    this.step = 0,
    this.steps = 0,
  });

  final JavaProvisionPhase phase;
  final DownloadProgress? download;
  final String? detail;
  final int step;
  final int steps;

  @override
  String toString() =>
      '${phase.name}${detail == null ? '' : ' ($detail)'}'
      '${download == null ? '' : ' ${download!}'}';
}

/// What a completed runtime install produced.
class JavaProvisionResult {
  const JavaProvisionResult({
    required this.root,
    required this.executable,
    required this.choice,
    required this.filesWritten,
    required this.bytesWritten,
    required this.skippedEntries,
  });

  /// Directory that is the runtime's `JAVA_HOME` (the bundle's `Home` on macOS).
  final String root;

  /// Absolute path to the `java` executable inside [root].
  final String executable;

  final JavaRuntimeChoice choice;
  final int filesWritten;
  final int bytesWritten;

  /// Manifest entries of a kind this launcher does not implement.
  final int skippedEntries;

  @override
  String toString() =>
      '${choice.component} ${choice.build.versionName} -> $executable';
}

/// Downloads and unpacks a Mojang JRE into the launcher's own runtime directory.
///
/// Staging discipline, copied from `VersionInstaller` because it is the part
/// that matters: everything is written into `<target>.staging`, and only a
/// fully extracted, link-completed runtime is renamed onto `<target>`. A cancel
/// or a corrupt object therefore never leaves a directory that `JavaManager.scan`
/// would advertise as a usable runtime — a half-JRE fails at launch with an
/// `UnsatisfiedLinkError` that looks like a Minecraft bug.
class JavaProvisioner {
  JavaProvisioner({
    HttpClient? client,
    MirrorChain? mirrors,
    FileDownloader? downloader,
    this.concurrency = 6,
  }) : _client = client ?? HttpClient(),
       mirrors = mirrors ?? MirrorChain(),
       _downloader =
           downloader ?? FileDownloader(client: client, mirrors: mirrors);

  final HttpClient _client;
  final MirrorChain mirrors;
  final FileDownloader _downloader;

  /// Runtime files are few and large, so this stays below the asset default:
  /// `lib/modules` alone is ~55 MB and six of those in parallel would swamp a
  /// slow connection without finishing any sooner.
  final int concurrency;

  /// Reads `all.json`. Served through `readSmallBody` so a captive portal's HTML
  /// cannot be parsed as a catalog.
  Future<JavaCatalog> fetchCatalog(Uri uri, {CancelToken? cancel}) async {
    cancel?.throwIfCancelled('java catalog');
    final request = await _client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode >= 400) {
      await response.drain<void>();
      throw HttpException('HTTP ${response.statusCode} from $uri', uri: uri);
    }
    final body = await readSmallBody(response);
    return JavaCatalog.fromJson(_decodeObject(body, 'java catalog'));
  }

  /// Reads one runtime's file manifest.
  Future<JavaRuntimeManifest> fetchManifest(
    JavaCatalogBuild build, {
    CancelToken? cancel,
  }) async {
    cancel?.throwIfCancelled('java manifest');
    final uri = Uri.parse(build.manifestUrl);
    final request = await _client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode >= 400) {
      await response.drain<void>();
      throw HttpException('HTTP ${response.statusCode} from $uri', uri: uri);
    }
    final body = await readSmallBody(response);
    return JavaRuntimeManifest.fromJson(_decodeObject(body, 'java manifest'));
  }

  /// Installs [choice] under [runtimesDir] and returns the finished runtime.
  ///
  /// [runtimesDir] is the launcher's own `<data>/runtimes`; the resulting
  /// directory is `<runtimesDir>/<component>-<version>`, which is what
  /// `JavaManager.managedRoots` should be pointed at.
  Future<JavaProvisionResult> provision({
    required JavaRuntimeChoice choice,
    required JavaRuntimeManifest manifest,
    required Directory runtimesDir,
    required HostOs hostOs,
    CancelToken? cancel,
    void Function(JavaProvisionProgress)? onProgress,
  }) async {
    const steps = 5;
    void phase(
      JavaProvisionPhase p, {
      String? detail,
      int step = 0,
      DownloadProgress? download,
    }) => onProgress?.call(
      JavaProvisionProgress(
        phase: p,
        detail: detail,
        step: step,
        steps: steps,
        download: download,
      ),
    );

    final name = runtimeDirName(choice);
    final target = Directory(p.join(runtimesDir.path, name));
    Directory? staging = Directory('${target.path}.staging');

    phase(JavaProvisionPhase.manifest, step: 1, detail: name);

    // A previous attempt may have died mid-extract; the staging tree is only
    // ever a means to an end, so it is always discarded rather than resumed.
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);

    try {
      phase(JavaProvisionPhase.download, step: 2);
      final fetched = await _fetchAll(
        manifest: manifest,
        staging: staging,
        cancel: cancel,
        onProgress: (progress) =>
            phase(JavaProvisionPhase.download, step: 2, download: progress),
      );

      cancel?.throwIfCancelled('java extract');
      phase(
        JavaProvisionPhase.extract,
        step: 3,
        detail: '${fetched.length} file(s)',
      );
      var bytes = 0;
      for (final entry in fetched) {
        bytes += await _materialize(entry, staging, cancel: cancel);
      }
      // Every object has been expanded; the cache directory itself is the last
      // thing standing between the staging tree and a clean runtime.
      final objects = Directory(p.join(staging.path, _objectsDir));
      if (await objects.exists()) await objects.delete(recursive: true);

      phase(
        JavaProvisionPhase.links,
        step: 4,
        detail: '${manifest.links.length}',
      );
      // Link targets are files, so they exist by now; a link to a directory
      // would not, and the real manifests only link within `legal/`.
      await _materializeLinks(
        manifest.links.toList(),
        staging,
        hostOs: hostOs,
        cancel: cancel,
      );

      phase(JavaProvisionPhase.verify, step: 5, detail: name);
      final executable = p.join(
        staging.path,
        manifest.javaExecutable(os: hostOs),
      );
      if (!File(executable).existsSync()) {
        throw StateError(
          'java runtime manifest for $name has no executable at '
          '${manifest.javaExecutable(os: hostOs)}',
        );
      }

      // Only now is the runtime real. `rename` onto an existing target would
      // fail on Windows and silently nest on POSIX, so any previous install is
      // removed first — it is being replaced on purpose.
      cancel?.throwIfCancelled('java finalize');
      if (await target.exists()) await target.delete(recursive: true);
      await staging.rename(target.path);
      // `staging` is now `target`; clear it so the catch below does not try to
      // delete a path that no longer exists (and must not delete `target`).
      staging = null;

      return JavaProvisionResult(
        root: target.path,
        executable: p.join(target.path, manifest.javaExecutable(os: hostOs)),
        choice: choice,
        filesWritten: fetched.length,
        bytesWritten: bytes,
        skippedEntries: manifest.skipped,
      );
    } catch (_) {
      // Cancelled or failed: leave nothing behind that looks installed.
      if (staging != null && await staging.exists()) {
        await staging.delete(recursive: true);
      }
      rethrow;
    }
  }

  /// Downloads every file entry, returning the entries with the object that was
  /// actually fetched attached.
  Future<List<_FetchedEntry>> _fetchAll({
    required JavaRuntimeManifest manifest,
    required Directory staging,
    CancelToken? cancel,
    void Function(DownloadProgress)? onProgress,
  }) async {
    final objects = Directory(p.join(staging.path, _objectsDir));
    final tasks = <DownloadTask>[];
    final byPath = <String, _FetchedEntry>{};

    for (final entry in manifest.files) {
      final object = entry.preferredDownload;
      if (object == null) continue;
      final relative = safeRelativeEntryName(entry.path, 'java runtime');
      // Keyed by hash, so two entries that name the same object (a file and the
      // link target referring to it) download it once.
      final local = p.join(objects.path, object.sha1);
      tasks.add(
        DownloadTask(
          url: Uri.parse(object.url),
          targetPath: local,
          sha1: object.sha1,
          size: object.size,
        ),
      );
      byPath[local] = _FetchedEntry(
        entry: entry,
        relativePath: relative,
        localObjectPath: local,
        compressed: entry.isCompressed,
      );
    }

    if (tasks.isEmpty) {
      throw StateError('java runtime manifest has no downloadable files');
    }

    await for (final progress in _downloader.download(
      tasks,
      concurrency: concurrency,
      cancel: cancel,
    )) {
      onProgress?.call(progress);
    }
    cancel?.throwIfCancelled('java download');
    return byPath.values.toList();
  }

  /// Expands one downloaded object into its real path, dropping the object
  /// cache entry as it goes so peak disk use is the runtime plus one file.
  Future<int> _materialize(
    _FetchedEntry fetched,
    Directory staging, {
    CancelToken? cancel,
  }) async {
    final objectFile = File(fetched.localObjectPath);
    final data = await objectFile.readAsBytes();

    final Uint8List bytes;
    if (fetched.compressed) {
      final rawSize = fetched.entry.raw?.size;
      if (rawSize == null || rawSize <= 0) {
        throw StateError(
          'java runtime entry ${fetched.entry.path} is compressed but the '
          'manifest declares no raw size',
        );
      }
      bytes = await decompressJavaObject(compressed: data, rawSize: rawSize);
    } else {
      bytes = data;
    }

    // The manifest is the only thing that says how big a file should be; a
    // mismatch means the decompressor disagreed with the catalog, which is
    // exactly the case where writing the file would produce a corrupt JRE.
    final expected = fetched.entry.raw?.size;
    if (expected != null && expected > 0 && bytes.length != expected) {
      throw StateError(
        'java runtime entry ${fetched.entry.path} is ${bytes.length}B, '
        'manifest declares ${expected}B',
      );
    }

    final target = File(p.join(staging.path, fetched.relativePath));
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes, flush: false);

    if (fetched.entry.executable) {
      await _makeExecutable(target);
    }

    await objectFile.delete();
    cancel?.throwIfCancelled('java extract');
    return bytes.length;
  }

  /// Turns `link` entries into symlinks, or copies where symlinks are not
  /// available (Windows, and a filesystem that refuses them).
  ///
  /// All 208 links in the real manifests live under `legal/` and point at
  /// `../java.base/…`, so they are licence text, not code — copying is a
  /// correct fallback, unlike copying a `lib/` link would be.
  Future<void> _materializeLinks(
    List<JavaFileEntry> links,
    Directory staging, {
    required HostOs hostOs,
    CancelToken? cancel,
  }) async {
    for (final link in links) {
      cancel?.throwIfCancelled('java links');
      final target = link.target;
      if (target == null || target.isEmpty) continue;

      final relative = safeRelativeEntryName(link.path, 'java runtime link');
      final destination = p.normalize(p.join(staging.path, relative));
      if (!p.isWithin(staging.path, destination)) {
        throw FormatException(
          'java runtime link escapes the runtime: ${link.path}',
        );
      }
      // The link target is relative to the link's own directory.
      final source = p.normalize(
        p.join(p.dirname(destination), target.replaceAll('\\', '/')),
      );
      if (!p.isWithin(staging.path, source) && source != staging.path) {
        throw FormatException(
          'java runtime link points outside the runtime: '
          '${link.path} -> $target',
        );
      }
      if (!File(source).existsSync()) {
        throw StateError(
          'java runtime link ${link.path} points at a missing file: $target',
        );
      }

      await Directory(p.dirname(destination)).create(recursive: true);
      if (await Link(destination).exists()) await Link(destination).delete();
      if (await File(destination).exists()) await File(destination).delete();

      var linked = false;
      if (hostOs != HostOs.windows) {
        try {
          await Link(destination).create(target);
          linked = true;
        } on FileSystemException {
          // A filesystem without symlink support (FAT, some network shares).
          linked = false;
        }
      }
      if (!linked) {
        await File(source).copy(destination);
      }
    }
  }

  static Future<void> _makeExecutable(File file) async {
    if (Platform.isWindows) return;
    await Process.run('chmod', ['+x', file.path]);
  }

  static Map<String, dynamic> _decodeObject(String body, String what) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      // A captive portal or a mirror error page, not a catalog.
      throw FormatException('$what is not valid JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('$what is not a JSON object');
    }
    return decoded;
  }

  void close() => _downloader.close();
}

/// The launcher's own runtime directory, e.g. `<data>/runtimes`.
Directory javaRuntimesDir(Directory data) =>
    Directory(p.join(data.path, 'runtimes'));

/// Search paths to hand to `JavaManager.scan`, one per installed runtime.
///
/// These are **`java` executables**, not directories: `scan` probes each entry
/// directly, so a runtime root here would be executed as if it were a program.
///
/// `.staging` trees are skipped on purpose. They are half-extracted by
/// definition, and probing one would find a `bin/java` that cannot start —
/// which is how a cancelled install becomes a phantom "Java 17 installed".
///
/// The macOS layout is why this probes the filesystem instead of assuming
/// `<root>/bin/java`: Mojang's Darwin manifests root the tree at
/// `jre.bundle/Contents/Home/`.
List<String> managedJavaExecutables(Directory data) {
  final dir = javaRuntimesDir(data);
  if (!dir.existsSync()) return const [];
  final executables = <String>[];
  for (final entry in dir.listSync()) {
    if (entry is! Directory) continue;
    if (entry.path.endsWith('.staging')) continue;
    for (final relative in _executableLayouts) {
      final candidate = File(p.join(entry.path, relative));
      if (candidate.existsSync()) {
        executables.add(candidate.path);
        break;
      }
    }
  }
  executables.sort();
  return executables;
}

/// Where a provisioned runtime may keep its `java`, in preference order.
const _executableLayouts = [
  'bin/java',
  'bin/java.exe',
  'jre.bundle/Contents/Home/bin/java',
  'Contents/Home/bin/java',
];

/// Where downloaded objects live inside the staging tree until expanded.
const _objectsDir = '.objects';

/// Directory name for [choice], stable across runs so re-installing replaces
/// rather than duplicates.
String runtimeDirName(JavaRuntimeChoice choice) =>
    '${choice.component}-${choice.build.versionName}';

class _FetchedEntry {
  _FetchedEntry({
    required this.entry,
    required this.relativePath,
    required this.localObjectPath,
    required this.compressed,
  });

  final JavaFileEntry entry;

  /// Normalised, known-relative destination.
  final String relativePath;

  final String localObjectPath;
  final bool compressed;
}
