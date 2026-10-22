import 'dart:io';

import '../mc/host.dart';

/// A Java runtime found on the machine.
class JavaRuntime {
  const JavaRuntime({
    required this.path,
    required this.majorVersion,
    required this.versionString,
    required this.vendor,
    required this.arch,
    this.is64Bit = true,
    this.source = JavaSource.scanned,
  });

  /// Absolute path to the `java` executable.
  final String path;

  /// Feature release, e.g. 8, 17, 21, 25.
  final int majorVersion;

  /// Full version string, e.g. `17.0.9+9`.
  final String versionString;

  final String vendor;
  final HostArch arch;
  final bool is64Bit;
  final JavaSource source;

  bool satisfies(int requiredMajor) => majorVersion >= requiredMajor;

  /// Minecraft's own rule of thumb: the runtime should be the *declared* major
  /// where possible, because mods assume it. Newer is accepted but flagged.
  bool isExactMatch(int requiredMajor) => majorVersion == requiredMajor;

  @override
  String toString() =>
      'Java $majorVersion ($versionString, ${arch.mcName}) @ $path';

  Map<String, dynamic> toJson() => {
    'path': path,
    'major': majorVersion,
    'version': versionString,
    'vendor': vendor,
    'arch': arch.mcName,
    'is64': is64Bit,
  };

  factory JavaRuntime.fromJson(Map<String, dynamic> json) => JavaRuntime(
    path: json['path'] as String? ?? '',
    majorVersion: (json['major'] as num?)?.toInt() ?? 0,
    versionString: json['version'] as String? ?? '',
    vendor: json['vendor'] as String? ?? '',
    arch: HostArch.fromMcName(json['arch'] as String? ?? '') ?? HostArch.x86_64,
    is64Bit: json['is64'] as bool? ?? true,
  );
}

enum JavaSource {
  /// Found by probing an executable on this machine.
  scanned,

  /// Downloaded and managed by the launcher.
  managed,

  /// Chosen explicitly by the user for an instance.
  manual,
}

/// Runs `java -XshowSettings:properties -version` and parses the output.
///
/// That one invocation yields `java.version`, `os.arch` and `java.vendor` in a
/// stable `key = value` form, so we do not have to guess from the filename.
class JavaProbe {
  const JavaProbe({
    required this.runProcess,
    this.timeout = const Duration(seconds: 15),
  });

  /// Injected so tests can supply canned output instead of a real JVM.
  final Future<ProcessResultLike> Function(String exe, List<String> args)
  runProcess;

  final Duration timeout;

  Future<JavaRuntime?> probe(String executablePath) async {
    try {
      final result = await runProcess(executablePath, [
        '-XshowSettings:properties',
        '-version',
      ]);
      // `-version` writes to stderr, and the properties dump does too.
      final output = '${result.stdout}\n${result.stderr}';
      if (result.exitCode != 0 && !output.contains('java.version')) return null;
      return parseExecutableOutput(executablePath, output);
    } on ProcessException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  /// Parses the `key = value` dump. Kept separate so the parsing rules are
  /// unit-tested without spawning anything.
  static JavaRuntime? parseExecutableOutput(String path, String output) {
    final props = parseProperties(output);
    final versionString =
        props['java.version'] ?? props['java.runtime.version'];
    if (versionString == null || versionString.isEmpty) return null;

    final osArch = props['os.arch'] ?? '';
    final arch = switch (osArch) {
      'aarch64' || 'arm64' => HostArch.arm64,
      'x86' || 'i386' || 'i686' => HostArch.x86,
      'amd64' || 'x86_64' => HostArch.x86_64,
      // Empty means the dump was truncated: assume the common case rather than
      // declaring the runtime unusable.
      _ => HostArch.x86_64,
    };

    return JavaRuntime(
      path: path,
      majorVersion: majorFromVersionString(versionString),
      versionString: versionString,
      vendor: props['java.vendor'] ?? '',
      arch: arch,
      is64Bit: arch != HostArch.x86,
    );
  }

  /// Extracts `key = value` pairs from the settings dump.
  static Map<String, String> parseProperties(String output) {
    final result = <String, String>{};
    for (final rawLine in output.split('\n')) {
      final line = rawLine.trim();
      final idx = line.indexOf(' = ');
      if (idx <= 0) continue;
      final key = line.substring(0, idx).trim();
      // Only keep the keys we care about; the dump has dozens.
      if (!key.startsWith('java.') && !key.startsWith('os.')) continue;
      result[key] = line.substring(idx + 3).trim();
    }
    return result;
  }

  /// `1.8.0_402` → 8, `17.0.9` → 17, `25-ea` → 25, `1.7.0_80` → 7.
  static int majorFromVersionString(String version) {
    final cleaned = version.trim();
    final parts = cleaned.split(RegExp(r'[._+\-]'));
    if (parts.isEmpty) return 0;
    if (parts.first == '1' && parts.length > 1) {
      return int.tryParse(parts[1]) ?? 0;
    }
    final leading = RegExp(r'^\d+').stringMatch(parts.first);
    return leading == null ? 0 : int.parse(leading);
  }
}

/// Minimal view of a process result, so tests need no `dart:io` process.
class ProcessResultLike {
  const ProcessResultLike({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// A place to look for JDKs: a directory whose subdirectories are JDK homes,
/// plus the path to `java` relative to each home.
class JavaSearchRoot {
  const JavaSearchRoot(
    this.directory,
    this.relativeExecutable, {
    this.depth = 1,
  });

  final String directory;
  final String relativeExecutable;

  /// How many directory levels below [directory] a runtime may live.
  ///
  /// System JDKs are `<root>/<jdk>/bin/java` (1). The launchers that manage their
  /// own runtimes nest deeper - Prism keeps `java/<vendor>/<version>/bin/java`,
  /// the official launcher `runtime/<flavour>/bin/java` - and those are exactly the
  /// JVMs a user who "can launch it in Prism" already has on disk.
  final int depth;
}

/// The per-OS install roots, independent of what exists on this machine.
///
/// Separated from [defaultJavaSearchPaths] so the *rule* can be asserted on any
/// host — a Linux CI box has no `C:\Program Files`, but the intent still needs
/// a test.
List<JavaSearchRoot> javaSearchRoots(HostOs os, {String? home}) {
  final h = home ?? '';
  return switch (os) {
    HostOs.windows => [
      const JavaSearchRoot(r'C:\Program Files\Java', r'bin\java.exe'),
      const JavaSearchRoot(
        r'C:\Program Files\Eclipse Adoptium',
        r'bin\java.exe',
      ),
      const JavaSearchRoot(r'C:\Program Files\Microsoft', r'bin\java.exe'),
      const JavaSearchRoot(r'C:\Program Files\Zulu', r'bin\java.exe'),
      const JavaSearchRoot(r'C:\Program Files (x86)\Java', r'bin\java.exe'),
      // Launcher-managed runtimes: launching a 26.x profile in Prism or the
      // official launcher works because *they* shipped the JVM.
      if (h.isNotEmpty)
        JavaSearchRoot('$h\\PrismLauncher\\java', r'bin\java.exe', depth: 3),
      if (h.isNotEmpty) JavaSearchRoot('$h\\.jdks', r'bin\java.exe', depth: 2),
    ],
    HostOs.osx => [
      const JavaSearchRoot(
        '/Library/Java/JavaVirtualMachines',
        'Contents/Home/bin/java',
        depth: 1,
      ),
      if (h.isNotEmpty)
        JavaSearchRoot(
          '$h/Library/Java/JavaVirtualMachines',
          'Contents/Home/bin/java',
        ),
      if (h.isNotEmpty)
        JavaSearchRoot(
          '$h/Library/Application Support/PrismLauncher/java',
          'bin/java',
          depth: 3,
        ),
    ],
    HostOs.linux => [
      const JavaSearchRoot('/usr/lib/jvm', 'bin/java'),
      const JavaSearchRoot('/usr/java', 'bin/java'),
      const JavaSearchRoot('/opt', 'bin/java', depth: 2),
      if (h.isNotEmpty) ...[
        // IntelliJ / sdkman: a JVM the user installed on purpose.
        JavaSearchRoot('$h/.jdks', 'bin/java', depth: 2),
        JavaSearchRoot('$h/.sdkman/candidates/java', 'bin/java', depth: 2),
        // Other launchers' bundled runtimes. This is the case that matters: a
        // version that runs in Prism has a JVM *there*, and the user should not
        // have to download a second copy of it.
        JavaSearchRoot(
          '$h/.local/share/PrismLauncher/java',
          'bin/java',
          depth: 3,
        ),
        JavaSearchRoot(
          '$h/.var/app/org.prismlauncher.PrismLauncher/data/PrismLauncher/java',
          'bin/java',
          depth: 3,
        ),
        JavaSearchRoot('$h/.minecraft/runtime', 'bin/java', depth: 2),
        JavaSearchRoot(
          '$h/.var/app/com.mojang.Minecraft/.minecraft/runtime',
          'bin/java',
          depth: 2,
        ),
      ],
    ],
  };
}

/// Where to look for a `java` executable.
///
/// Ordered by likelihood: an explicit override, the launcher's own managed
/// runtimes, `JAVA_HOME`, then the usual per-OS install roots.
///
/// [managedRoots] holds executable paths, not directories — `scan` probes every
/// entry directly, so a directory would be run as if it were a program.
List<String> defaultJavaSearchPaths({
  required HostOs os,
  String? javaHome,
  List<String> managedRoots = const [],
  Map<String, String> env = const {},

  /// Directories the user pointed at, scanned like an install root (one level of
  /// subdirectories, plus the directory itself).
  List<String> extraRoots = const [],
}) {
  final paths = <String>[...managedRoots];

  final home = javaHome ?? env['JAVA_HOME'];
  if (home != null && home.isNotEmpty) {
    final sep = os == HostOs.windows ? r'\' : '/';
    paths.add('$home${sep}bin${sep}java${os == HostOs.windows ? '.exe' : ''}');
  }

  for (final dir in extraRoots) {
    final sep = os == HostOs.windows ? r'\' : '/';
    final exe = 'bin${sep}java${os == HostOs.windows ? '.exe' : ''}';
    // The directory may be a JDK home itself, or a folder of them (a toolchain
    // manager's layout), so both are offered.
    final direct = File('$dir$sep$exe');
    if (direct.existsSync()) paths.add(direct.path);
    paths.addAll(
      _subdirsWithJava(
        dir,
        'bin/${os == HostOs.windows ? 'java.exe' : 'java'}',
        2,
      ),
    );
  }

  final userHome = env['HOME'] ?? env['USERPROFILE'];
  for (final root in javaSearchRoots(os, home: userHome)) {
    paths.addAll(
      _subdirsWithJava(root.directory, root.relativeExecutable, root.depth),
    );
  }

  switch (os) {
    case HostOs.windows:
      break;
    case HostOs.osx:
      paths.addAll(const [
        '/opt/homebrew/opt/openjdk/bin/java',
        '/usr/local/opt/openjdk/bin/java',
      ]);
    case HostOs.linux:
      paths.add('/usr/bin/java');
  }
  return paths;
}

List<String> _subdirsWithJava(String root, String relative, [int depth = 1]) {
  final found = <String>[];
  _collectJava(Directory(root), relative, depth, found, {root});
  found.sort();
  return found;
}

/// Walks [dir] at most [depth] levels, collecting `relative` executables.
///
/// Depth-limited rather than a full walk: `$HOME` can hold a hundred thousand
/// files, and a launcher that stat()s them all at startup is worse than one that
/// misses a JVM in an unusual place.
void _collectJava(
  Directory dir,
  String relative,
  int depth,
  List<String> out,
  Set<String> visited,
) {
  if (depth <= 0 || !dir.existsSync()) return;
  List<FileSystemEntity> entries;
  try {
    entries = dir.listSync(followLinks: false);
  } on FileSystemException {
    // Permission-denied or a broken mount under a home directory is normal.
    return;
  }
  for (final entry in entries) {
    if (entry is! Directory) continue;
    // A symlinked JDK directory is common (`/opt/java/openjdk -> ...`), so links
    // are followed once, guarded against cycles.
    if (!visited.add(entry.path)) continue;
    final candidate = File('${entry.path}/$relative');
    if (candidate.existsSync()) {
      out.add(candidate.path);
      continue;
    }
    _collectJava(entry, relative, depth - 1, out, visited);
  }
}

/// Picks the best runtime for a required major version.
///
/// Prefers an exact major match (mods assume it), then the lowest newer major,
/// and never returns a runtime older than required. Returns `null` when nothing
/// on the machine qualifies — the caller then offers to download one.
JavaRuntime? selectRuntime(List<JavaRuntime> available, int requiredMajor) {
  final usable = available.where((j) => j.satisfies(requiredMajor)).toList();
  if (usable.isEmpty) return null;
  usable.sort((a, b) {
    final aExact = a.isExactMatch(requiredMajor) ? 0 : 1;
    final bExact = b.isExactMatch(requiredMajor) ? 0 : 1;
    if (aExact != bExact) return aExact.compareTo(bExact);
    final byMajor = a.majorVersion.compareTo(b.majorVersion);
    if (byMajor != 0) return byMajor;
    // Prefer a 64-bit runtime, then a launcher-managed one.
    if (a.is64Bit != b.is64Bit) return a.is64Bit ? -1 : 1;
    // Both comparisons must be antisymmetric. Returning 1 whenever `a` was not
    // managed made "scanned vs managed" and "managed vs scanned" both report
    // "a is greater", so the sort was inconsistent and the winner depended on
    // the order runtimes happened to be discovered in.
    if (a.source != b.source) {
      return a.source == JavaSource.managed ? -1 : 1;
    }
    return 0;
  });
  return usable.first;
}

/// Scans the machine once and caches, since probing a JVM costs ~100 ms each.
class JavaManager {
  JavaManager({
    required this.hostOs,
    JavaProbe? probe,
    List<JavaRuntime> known = const [],
  }) : probe =
           probe ??
           JavaProbe(
             runProcess: (exe, args) async {
               final r = await Process.run(exe, args);
               return ProcessResultLike(
                 exitCode: r.exitCode,
                 stdout: '${r.stdout}',
                 stderr: '${r.stderr}',
               );
             },
           ),
       _runtimes = List.of(known);

  final HostOs hostOs;
  final JavaProbe probe;
  final List<JavaRuntime> _runtimes;

  bool _scanned = false;

  List<JavaRuntime> get runtimes => List.unmodifiable(_runtimes);

  Future<List<JavaRuntime>> scan({
    String? javaHome,
    List<String> managedRoots = const [],
    List<String> extraRoots = const [],
    Map<String, String>? environment,
  }) async {
    _scanned = true;
    final seen = {for (final r in _runtimes) r.path};
    // A runtime found under one of our own directories is ours: it is the
    // launcher's to replace or delete, and `selectRuntime` prefers it on a tie.
    // Without this every provisioned JRE would be indistinguishable from a
    // system JDK, and "delete the runtime we downloaded" would have no way to
    // know which ones it may touch.
    final managed = managedRoots.toSet();
    for (final path in defaultJavaSearchPaths(
      os: hostOs,
      javaHome: javaHome,
      managedRoots: managedRoots,
      env: environment ?? Platform.environment,
      extraRoots: extraRoots,
    )) {
      if (!seen.add(path)) continue;
      final runtime = await probe.probe(path);
      if (runtime == null) continue;
      _runtimes.add(
        managed.contains(path)
            ? JavaRuntime(
                path: runtime.path,
                majorVersion: runtime.majorVersion,
                versionString: runtime.versionString,
                vendor: runtime.vendor,
                arch: runtime.arch,
                is64Bit: runtime.is64Bit,
                source: JavaSource.managed,
              )
            : runtime,
      );
    }
    _runtimes.sort((a, b) => a.majorVersion.compareTo(b.majorVersion));
    return runtimes;
  }

  bool get hasScanned => _scanned;

  void add(JavaRuntime runtime) {
    _runtimes.removeWhere((r) => r.path == runtime.path);
    _runtimes.add(runtime);
    _runtimes.sort((a, b) => a.majorVersion.compareTo(b.majorVersion));
  }

  /// Every distinct major version present, for the settings screen.
  List<int> get majors =>
      _runtimes.map((r) => r.majorVersion).toSet().toList()..sort();
}
