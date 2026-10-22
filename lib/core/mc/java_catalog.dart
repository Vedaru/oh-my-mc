/// Mojang's Java runtime catalog: what runtimes exist, for which platform, and
/// the per-file manifest that describes one.
///
/// Two documents, both plain JSON from `launchermeta`:
///
///  * `all.json` — platform → component (`jre-legacy`, `java-runtime-gamma`, …)
///    → available builds, each with a URL to a file manifest.
///  * that file manifest — one entry per path: a file (with `raw` and usually
///    `lzma` objects), a directory, or a `link` to a sibling path.
///
/// Parsed as pure value types with no I/O, so every platform's rules can be
/// exercised from one machine. The downloader lives in `java_provisioner.dart`.
library;

import 'host.dart';

/// Where `all.json` lives. The trailing hash is Mojang's, not ours.
const javaCatalogUri =
    'https://launchermeta.mojang.com/v1/products/java-runtime/'
    '2ec0cc96c44e5a76b9c8b7c39df7210883d12871/all.json';

/// The largest single runtime file we will accept, as a guard against a
/// manifest that inflates `raw.size` to make us allocate. The biggest real
/// entry is `lib/modules` at ~55 MB; `assets` are governed separately.
const maxJavaRuntimeFileBytes = 512 * 1024 * 1024;

/// The catalog calls macOS `mac-os`, not `osx`, and distinguishes 32-bit Linux.
/// Building this from `HostOs.mcName` would silently produce `osx`.
String javaPlatformKey(HostOs os, HostArch arch) => switch ((os, arch)) {
  (HostOs.windows, HostArch.x86_64) => 'windows-x64',
  (HostOs.windows, HostArch.x86) => 'windows-x86',
  (HostOs.windows, HostArch.arm64) => 'windows-arm64',
  (HostOs.osx, HostArch.arm64) => 'mac-os-arm64',
  // There is no x86 (32-bit) macOS runtime in the catalog; Intel Macs use the
  // x86_64 key, which is what `mac-os` is.
  (HostOs.osx, _) => 'mac-os',
  (HostOs.linux, HostArch.x86) => 'linux-i386',
  (HostOs.linux, _) => 'linux',
};

/// One downloadable object: `raw` bytes or an LZMA-compressed copy.
class JavaObject {
  const JavaObject({required this.url, required this.sha1, required this.size});

  factory JavaObject.fromJson(Map<String, dynamic> json) => JavaObject(
    url: json['url'] as String? ?? '',
    sha1: (json['sha1'] as String? ?? '').toLowerCase(),
    size: (json['size'] as num?)?.toInt() ?? 0,
  );

  final String url;

  /// Expected SHA-1 of *this* object, lowercase hex. For `lzma` this is the hash
  /// of the compressed bytes, so it is verified before decompression.
  final String sha1;

  final int size;

  bool get isUsable => url.isNotEmpty && sha1.isNotEmpty && size > 0;
}

/// One entry of a runtime file manifest.
enum JavaEntryKind {
  file,
  directory,

  /// A relative symlink. 208 of these exist on Linux/macOS, all under `legal/`,
  /// with `..`-relative targets. Windows manifests have none.
  link,
}

class JavaFileEntry {
  const JavaFileEntry({
    required this.path,
    required this.kind,
    this.executable = false,
    this.target,
    this.raw,
    this.lzma,
  });

  /// Parses one `files` entry. Returns `null` for an unknown `type` rather than
  /// throwing: the catalog gains entry kinds over time and refusing to install
  /// a whole runtime over one entry we do not understand would be worse than
  /// ignoring it.
  static JavaFileEntry? tryParse(String path, Map<String, dynamic> json) {
    final kind = switch (json['type']) {
      'file' => JavaEntryKind.file,
      'directory' => JavaEntryKind.directory,
      'link' => JavaEntryKind.link,
      _ => null,
    };
    if (kind == null) return null;

    final downloads = json['downloads'];
    JavaObject? object(String key) {
      if (downloads is! Map<String, dynamic>) return null;
      final raw = downloads[key];
      if (raw is! Map<String, dynamic>) return null;
      final parsed = JavaObject.fromJson(raw);
      return parsed.isUsable ? parsed : null;
    }

    return JavaFileEntry(
      path: path,
      kind: kind,
      executable: json['executable'] as bool? ?? false,
      target: json['target'] as String?,
      raw: kind == JavaEntryKind.file ? object('raw') : null,
      lzma: kind == JavaEntryKind.file ? object('lzma') : null,
    );
  }

  /// Manifest-relative path, e.g. `bin/java` or `jre.bundle/Contents/Home/bin/java`.
  final String path;

  final JavaEntryKind kind;
  final bool executable;

  /// For [JavaEntryKind.link]: the sibling this points at, e.g.
  /// `../java.base/LICENSE`.
  final String? target;

  final JavaObject? raw;

  /// Usually present (126 of 133 files in the measured 17.0.15 build). Absent
  /// for `lib/modules`, which is the single largest file.
  final JavaObject? lzma;

  /// The object to fetch: the smaller one.
  ///
  /// Usually that is the compressed object (12.6 MB instead of 39.5 MB across
  /// the 17.0.15 build), but LZMA has real per-file overhead and Mojang compresses
  /// some trivially small files where the compressed copy comes out *larger*.
  /// Taking the minimum keeps the "use lzma" win without ever paying for it.
  JavaObject? get preferredDownload {
    final compressed = lzma;
    final plain = raw;
    if (compressed == null) return plain;
    if (plain == null) return compressed;
    return compressed.size <= plain.size ? compressed : plain;
  }

  bool get isCompressed => lzma != null;

  /// Bytes this entry contributes to the wire total.
  int get wireBytes => preferredDownload?.size ?? 0;

  /// Bytes it contributes once materialised.
  int get diskBytes => raw?.size ?? 0;

  /// Where the `java` executable is, relative to the runtime root.
  bool get isJavaExecutable =>
      executable && (path.endsWith('/java') || path.endsWith('/java.exe'));
}

/// A runtime file manifest: the complete file list for one JRE build.
class JavaRuntimeManifest {
  const JavaRuntimeManifest({required this.entries, this.skipped = 0});

  factory JavaRuntimeManifest.fromJson(Map<String, dynamic> json) {
    final files = json['files'];
    if (files is! Map<String, dynamic>) {
      throw const FormatException('java runtime manifest has no "files"');
    }
    final entries = <JavaFileEntry>[];
    var skipped = 0;
    for (final entry in files.entries) {
      final value = entry.value;
      if (value is! Map<String, dynamic>) {
        skipped++;
        continue;
      }
      final parsed = JavaFileEntry.tryParse(entry.key, value);
      if (parsed == null) {
        skipped++;
        continue;
      }
      entries.add(parsed);
    }
    if (entries.isEmpty) {
      throw const FormatException(
        'java runtime manifest lists no usable files',
      );
    }
    return JavaRuntimeManifest(entries: entries, skipped: skipped);
  }

  final List<JavaFileEntry> entries;

  /// Entries whose `type` this version of the launcher does not implement.
  final int skipped;

  Iterable<JavaFileEntry> get files =>
      entries.where((e) => e.kind == JavaEntryKind.file);

  Iterable<JavaFileEntry> get links =>
      entries.where((e) => e.kind == JavaEntryKind.link);

  /// Malformed manifests are the difference between "download 96 MB" and
  /// "download 0 bytes and report success", so a manifest with no files at all
  /// is refused here rather than discovered as an empty runtime directory.
  int get wireBytes => files.fold(0, (sum, e) => sum + e.wireBytes);

  int get diskBytes => files.fold(0, (sum, e) => sum + e.diskBytes);

  /// The executable path if the manifest names one, else the conventional
  /// `<root>/bin/java` for this platform.
  ///
  /// macOS roots its tree at `jre.bundle/Contents/Home/`, so the conventional
  /// path is wrong there; this is why the manifest, not a guess, decides.
  String javaExecutable({required HostOs os}) {
    for (final entry in entries) {
      if (entry.isJavaExecutable) return entry.path;
    }
    return os == HostOs.windows ? 'bin/java.exe' : 'bin/java';
  }
}

/// One available build of a component on one platform.
class JavaCatalogBuild {
  const JavaCatalogBuild({
    required this.versionName,
    required this.manifestUrl,
    required this.manifestSha1,
    required this.manifestSize,
    this.released,
  });

  static JavaCatalogBuild? tryParse(Map<String, dynamic> json) {
    final version = json['version'];
    final manifest = json['manifest'];
    if (version is! Map<String, dynamic> || manifest is! Map<String, dynamic>) {
      return null;
    }
    final url = manifest['url'] as String? ?? '';
    final name = version['name'] as String? ?? '';
    if (url.isEmpty || name.isEmpty) return null;
    return JavaCatalogBuild(
      versionName: name,
      manifestUrl: url,
      manifestSha1: (manifest['sha1'] as String? ?? '').toLowerCase(),
      manifestSize: (manifest['size'] as num?)?.toInt() ?? 0,
      released: DateTime.tryParse(version['released'] as String? ?? ''),
    );
  }

  final String versionName;
  final String manifestUrl;
  final String manifestSha1;
  final int manifestSize;
  final DateTime? released;

  @override
  String toString() => versionName;
}

/// The parsed `all.json`.
class JavaCatalog {
  const JavaCatalog(this.platforms);

  factory JavaCatalog.fromJson(Map<String, dynamic> json) {
    final platforms = <String, Map<String, List<JavaCatalogBuild>>>{};
    for (final platform in json.entries) {
      final components = platform.value;
      if (components is! Map<String, dynamic>) continue;
      final parsed = <String, List<JavaCatalogBuild>>{};
      for (final component in components.entries) {
        final builds = component.value;
        if (builds is! List) continue;
        parsed[component.key] = [
          for (final build in builds)
            if (build is Map<String, dynamic>)
              ?JavaCatalogBuild.tryParse(build),
        ];
      }
      platforms[platform.key] = parsed;
    }
    if (platforms.isEmpty) {
      throw const FormatException('java runtime catalog has no platforms');
    }
    return JavaCatalog(platforms);
  }

  final Map<String, Map<String, List<JavaCatalogBuild>>> platforms;

  List<String> get platformKeys => platforms.keys.toList()..sort();

  /// The builds of [component] on [platform]; empty when the platform lists the
  /// component but publishes nothing for it.
  ///
  /// `mac-os-arm64` and `windows-arm64` really do list `jre-legacy`,
  /// `java-runtime-alpha` and `java-runtime-beta` as empty arrays, so "the key
  /// exists" does not mean "it is downloadable".
  List<JavaCatalogBuild> builds(String platform, String component) =>
      platforms[platform]?[component] ?? const [];

  Map<String, List<JavaCatalogBuild>> componentsFor(String platform) =>
      platforms[platform] ?? const {};

  /// Components that actually have a build on [platform], newest release kind
  /// first is *not* assumed — the caller picks by major version.
  Iterable<String> availableComponents(String platform) =>
      componentsFor(platform).entries
          .where((e) => e.value.isNotEmpty)
          .map((e) => e.key);
}

/// Which JRE a Minecraft version wants.
///
/// `javaVersion.component` is the catalog key verbatim, so this table exists
/// only to derive a component when a version JSON does not name one (pre-1.13
/// metadata has no `javaVersion` block at all) and to rank candidates by the
/// Java major they provide.
const javaComponentMajors = <String, int>{
  'jre-legacy': 8,
  'java-runtime-alpha': 16,
  'java-runtime-beta': 17,
  'java-runtime-gamma-snapshot': 17,
  'java-runtime-gamma': 17,
  'java-runtime-delta': 21,
  'java-runtime-epsilon': 25,
};

/// Tie-break order for components that provide the same major: the current
/// build first, then the older ones. `gamma` is the shipping Java 17 runtime;
/// `beta` and `gamma-snapshot` also declare 17.
const _componentPreference = <String>[
  'java-runtime-gamma',
  'java-runtime-beta',
  'java-runtime-gamma-snapshot',
  'java-runtime-delta',
  'java-runtime-epsilon',
  'java-runtime-alpha',
  'jre-legacy',
];

/// Thrown when this platform has no runtime that can satisfy [requiredMajor].
///
/// A distinct type, not a generic failure: the UI must say "Java 8 cannot be
/// downloaded on this machine" (an arm64 Mac) rather than "download failed",
/// because retrying will never help.
class JavaUnavailableException implements Exception {
  const JavaUnavailableException({
    required this.platform,
    required this.requiredMajor,
    this.requestedComponent,
  });

  final String platform;
  final int requiredMajor;
  final String? requestedComponent;

  @override
  String toString() =>
      'no Java $requiredMajor runtime is published for $platform'
      '${requestedComponent == null ? '' : ' (requested $requestedComponent)'}';
}

/// The chosen runtime for a version on a platform.
class JavaRuntimeChoice {
  const JavaRuntimeChoice({
    required this.component,
    required this.majorVersion,
    required this.build,
  });

  final String component;
  final int majorVersion;
  final JavaCatalogBuild build;

  @override
  String toString() => '$component ${build.versionName} (Java $majorVersion)';
}

/// A major version newer than the required one is only a safe substitute on the
/// modern line. Minecraft 1.13+ runs on any newer LTS, so "declared 21, got 25"
/// is fine — but a pre-1.13 version genuinely needs Java 8, and a Java 17 JVM
/// refuses its LWJGL2 natives outright. Offering 17 where 8 was asked for would
/// install cleanly and then fail at launch with an `UnsupportedClassVersion`
/// error, so it is refused instead.
const _newerMajorIsSafeFrom = 16;

/// Picks the runtime for [requiredMajor] on [platform].
///
/// Precedence, and why:
///
///  1. [declaredComponent] when the platform actually publishes it. The version
///     JSON names the exact runtime Mojang tested the game against.
///  2. Any component providing exactly [requiredMajor].
///  3. On the modern line, the lowest component providing more than
///     [requiredMajor] — same rule `selectRuntime` applies to local JVMs.
///  4. Otherwise nothing, which is the honest answer for Java 8 on Apple
///     Silicon: the catalog has no arm64 `jre-legacy`, and an x86_64 JRE that
///     cannot start is worse than saying so.
///
/// Throws [JavaUnavailableException] when no rule matches.
JavaRuntimeChoice chooseJavaRuntime({
  required JavaCatalog catalog,
  required String platform,
  required int requiredMajor,
  String? declaredComponent,
}) {
  final available = catalog.componentsFor(platform);

  JavaRuntimeChoice? choiceFor(String component) {
    final builds = available[component] ?? const <JavaCatalogBuild>[];
    final major = javaComponentMajors[component];
    if (builds.isEmpty || major == null) return null;
    return JavaRuntimeChoice(
      component: component,
      majorVersion: major,
      build: builds.first,
    );
  }

  if (declaredComponent != null) {
    final declared = choiceFor(declaredComponent);
    if (declared != null) return declared;
  }

  final candidates = <JavaRuntimeChoice>[
    for (final component in available.keys) ?choiceFor(component),
  ];
  final usable = candidates
      .where(
        (c) =>
            c.majorVersion == requiredMajor ||
            (requiredMajor >= _newerMajorIsSafeFrom &&
                c.majorVersion > requiredMajor),
      )
      .toList();
  if (usable.isEmpty) {
    throw JavaUnavailableException(
      platform: platform,
      requiredMajor: requiredMajor,
      requestedComponent: declaredComponent,
    );
  }

  int rank(JavaRuntimeChoice c) {
    final index = _componentPreference.indexOf(c.component);
    return index == -1 ? _componentPreference.length : index;
  }

  usable.sort((a, b) {
    final aExact = a.majorVersion == requiredMajor ? 0 : 1;
    final bExact = b.majorVersion == requiredMajor ? 0 : 1;
    if (aExact != bExact) return aExact.compareTo(bExact);
    final byMajor = a.majorVersion.compareTo(b.majorVersion);
    if (byMajor != 0) return byMajor;
    return rank(a).compareTo(rank(b));
  });

  return usable.first;
}

/// The component a bare major version maps to, for metadata with no
/// `javaVersion` block (everything pre-1.13, which needs Java 8).
String componentForMajor(int major) {
  var best = 'jre-legacy';
  var bestMajor = 8;
  for (final entry in javaComponentMajors.entries) {
    final m = entry.value;
    final closer = (m - major).abs() < (bestMajor - major).abs();
    final tieBreak =
        (m - major).abs() == (bestMajor - major).abs() &&
        _componentPreference.indexOf(entry.key) <
            _componentPreference.indexOf(best);
    if (closer || tieBreak) {
      best = entry.key;
      bestMajor = m;
    }
  }
  return best;
}
