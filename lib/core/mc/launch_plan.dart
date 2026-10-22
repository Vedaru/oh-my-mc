import 'version_json.dart';

/// Everything needed to hand a version to a JVM, resolved for one host.
class LaunchPlan {
  const LaunchPlan({
    required this.executable,
    required this.args,
    required this.classpath,
    required this.nativeArchives,
    required this.mainClass,
    required this.workingDirectory,
  });

  final String executable;
  final List<String> args;
  final List<String> classpath;
  final List<String> nativeArchives;
  final String mainClass;
  final String workingDirectory;

  /// The full command line, for logs and for "copy diagnostic info" in the UI.
  List<String> get commandLine => [executable, ...args];

  @override
  String toString() => commandLine.join(' ');
}

/// Assembles `java <jvmArgs> <mainClass> <gameArgs>`.
///
/// The classpath and native lists are passed explicitly (rather than baked into
/// [jvmArgs]) so the caller can verify every file exists before spawning, which
/// turns a mystifying JVM "Could not find or load main class" into a precise
/// missing-file report.
LaunchPlan assembleLaunchPlan({
  required String javaExecutable,
  required List<String> jvmArgs,
  required List<String> gameArgs,
  required String mainClass,
  required String workingDirectory,
  required List<String> classpath,
  required List<String> nativeArchives,
  String? jarOverride,
  String? separator,
}) {
  final sep = separator ?? classpathSeparator;
  final joined = jarOverride != null
      ? [jarOverride, ...classpath].join(sep)
      : classpath.join(sep);

  // Replace the literal ${classpath} the version metadata already contains.
  final resolvedJvm = [
    for (final a in jvmArgs) a.replaceAll(r'${classpath}', joined),
  ];

  return LaunchPlan(
    executable: javaExecutable,
    args: [...resolvedJvm, mainClass, ...gameArgs],
    classpath: classpath,
    nativeArchives: nativeArchives,
    mainClass: mainClass,
    workingDirectory: workingDirectory,
  );
}

/// `;` on Windows, `:` elsewhere. Kept here so the whole core agrees and tests
/// can assert both branches without touching `Platform`.
String classpathSeparatorFor(String osName) => osName == 'windows' ? ';' : ':';

/// Set by callers to the host separator; defaults to the POSIX one so pure tests
/// do not need `dart:io`.
String classpathSeparator = ':';

/// The client jar to hand to the JVM for [version].
///
/// Forge/Fabric set `jar` to point at the vanilla client of their parent, so an
/// instance's own client jar is not always the one to use.
String clientJarPath({
  required String versionId,
  required String? jarOverride,
  required String versionsRoot,
}) {
  final id = jarOverride ?? versionId;
  return '$versionsRoot/$id/$id.jar';
}

/// Where natives are unpacked for [versionId].
String nativesDirectoryFor(String versionId, String versionsRoot) =>
    '$versionsRoot/$versionId/natives';

/// Path to the log4j configuration a version asks for, if any.
String? log4jArgument(VersionJson version, String configPath) {
  final logging = version.raw['logging'];
  if (logging is! Map) return null;
  final client = logging['client'];
  if (client is! Map) return null;
  final arg = client['argument'];
  if (arg is! String) return null;
  return arg.replaceAll(r'${path}', configPath);
}
