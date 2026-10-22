import 'dart:io';

import 'package:path/path.dart' as p;

import 'arch_compat.dart';
import 'host.dart';
import 'install_plan.dart';
import 'java_manager.dart';
import 'jvm_args.dart';
import 'launch_plan.dart';
import 'library_graph.dart';
import 'version_json.dart';

/// What the player is launching as, and how.
class LaunchRequest {
  const LaunchRequest({
    required this.versionId,
    required this.playerName,
    required this.uuid,
    required this.accessToken,
    this.userType = 'msa',
    this.versionType = 'release',
    this.memoryMb,
    this.extraJvmArgs = const [],
    this.extraGameArgs = const [],
    this.features = const {},
    this.launcherName = 'oh my mc',
    this.launcherVersion = '0.1.0',
  });

  final String versionId;
  final String playerName;
  final String uuid;
  final String accessToken;
  final String userType;
  final String versionType;

  /// Heap cap. Applied as `-Xmx<memoryMb>M` ahead of the metadata's own flags.
  final int? memoryMb;

  /// Appended after the metadata's JVM block, before the main class.
  final List<String> extraJvmArgs;

  /// Appended after the metadata's game args, so a caller can override.
  final List<String> extraGameArgs;

  final Map<String, bool> features;
  final String launcherName;
  final String launcherVersion;
}

/// The result of preparing a launch: either a command to run, or the reasons
/// it cannot be built.
sealed class LaunchOutcome {
  const LaunchOutcome();
}

class LaunchReady extends LaunchOutcome {
  const LaunchReady({
    required this.plan,
    required this.java,
    required this.graph,
  });

  final LaunchPlan plan;
  final JavaRuntime java;
  final LibraryGraph graph;
}

class LaunchRefused extends LaunchOutcome {
  const LaunchRefused(this.blockers);

  final List<LaunchBlocker> blockers;

  @override
  String toString() => 'LaunchRefused(${blockers.join('; ')})';
}

/// Absolute, correctly ordered JVM `-cp` value for [version] on [host].
///
/// Three things go wrong if this is done inline at the call site, and all three
/// were real bugs in this repo:
///
///  * library paths were left relative (`com/google/...`), so the JVM resolved
///    them against the working directory and found nothing;
///  * the client jar was never added, so even a correct library set had no main
///    class to load;
///  * the platform separator came from a mutable global, which a test could set
///    for one OS and leak into another.
///
/// The client jar goes *last*, matching the vanilla launcher: metadata order in
/// front means a modloader's patched libraries win over the vanilla copies.
List<String> buildClasspath({
  required VersionJson version,
  required GamePaths paths,
  required List<String> libraryPaths,
}) {
  final clientJar = paths.versionJar(version.jar ?? version.id);
  return [
    for (final rel in libraryPaths)
      p.normalize(p.absolute(paths.libraryFile(rel))),
    p.normalize(p.absolute(clientJar)),
  ];
}

/// Builds the command line for [version], or explains why it cannot be built.
///
/// Reads only file *existence*, not contents: the caller has already installed
/// the version, so the question here is "is every file the JVM will be handed
/// actually there", which turns a bare `Could not find or load main class` into
/// a list of missing paths.
LaunchOutcome prepareLaunch({
  required VersionJson version,
  required GamePaths paths,
  required RuleContext host,
  required LaunchRequest request,
  required JavaRuntime? java,
  bool checkFiles = true,
}) {
  final graph = buildLibraryGraph(version, host, features: request.features);

  final blockers = <LaunchBlocker>[
    ...detectBlockers(version, graph, host.os, host.arch),
    ?checkJava(version, java?.majorVersion),
  ];

  if (java == null) {
    blockers.add(
      LaunchBlocker(
        code: BlockerCode.noRuntime,
        message: 'No Java runtime is available to start this version.',
        remedy: 'Install Java, or let the launcher download one.',
      ),
    );
  } else {
    final requiredMajor = version.javaVersion?.majorVersion;
    if (requiredMajor != null && !java.isExactMatch(requiredMajor)) {
      // Accepted on purpose: the game runs, but mods that assume the declared
      // major may not. Reported so the UI can offer the managed runtime.
      blockers.add(
        LaunchBlocker(
          code: BlockerCode.javaMajorMismatch,
          message:
              'This version declares Java $requiredMajor, but Java '
              '${java.majorVersion} is being used.',
          remedy:
              'Switch to a Java $requiredMajor runtime if the game misbehaves.',
        ),
      );
    }
  }

  final classpath = buildClasspath(
    version: version,
    paths: paths,
    libraryPaths: graph.classpathPaths,
  );

  if (checkFiles && java != null) {
    final missing = <String>[
      for (final path in classpath)
        if (!File(path).existsSync()) path,
      for (final archive in graph.natives)
        if (!File(_absolute(paths, archive.file.path)).existsSync())
          _absolute(paths, archive.file.path),
    ];
    if (missing.isNotEmpty) {
      blockers.add(
        LaunchBlocker(
          code: BlockerCode.missingFiles,
          message:
              '${missing.length} file(s) are missing from the install, '
              'starting with ${p.basename(missing.first)}.',
          remedy: 'Install the version again; the download is incomplete.',
        ),
      );
    }
  }

  // `noRuntime` and `missingFiles` are fatal: there is no command line to build.
  // The others are warnings the UI should show without refusing to start.
  final fatal = blockers.where(
    (b) =>
        b.code == BlockerCode.noRuntime ||
        b.code == BlockerCode.missingFiles ||
        b.code == BlockerCode.lwjgl2OnArm64Mac ||
        b.code == BlockerCode.allLibrariesFiltered ||
        b.code == BlockerCode.javaTooOld ||
        b.code == BlockerCode.missingNativeForHost,
  );
  if (fatal.isNotEmpty || java == null) {
    return LaunchRefused(blockers);
  }

  final separator = classpathSeparatorFor(host.os.mcName);

  final vars = LaunchVariables(
    authPlayerName: request.playerName,
    versionName: version.id,
    gameDirectory: p.normalize(p.absolute(paths.root)),
    assetsRoot: p.normalize(p.absolute(paths.assets)),
    assetIndexName: version.assetIndexName,
    authUuid: request.uuid,
    authAccessToken: request.accessToken,
    userType: request.userType,
    versionType: request.versionType,
    nativesDirectory: p.normalize(
      p.absolute(nativesDirectoryFor(version.id, paths.versions)),
    ),
    classpath: classpath.join(separator),
    launcherName: request.launcherName,
    launcherVersion: request.launcherVersion,
  );

  final metadataJvm = renderArguments(version, ArgSide.jvm, host, vars);
  final memory = request.memoryMb;
  final jvmArgs = [
    if (memory != null) '-Xmx${memory}M',
    ...metadataJvm,
    ...request.extraJvmArgs,
  ];

  // The metadata names the config file (`client-1.12.xml`); pointing the JVM at
  // the *directory* silently disables log4j and the game dies with no output.
  final log4jConfigId =
      (version.raw['logging']?['client']?['file']?['id'] as String?) ??
      'client.xml';
  final log4j = log4jArgument(
    version,
    p.join(paths.loggingConfigs, log4jConfigId),
  );
  final gameArgs = [
    ...renderArguments(version, ArgSide.game, host, vars),
    ?log4j,
    ...request.extraGameArgs,
  ];

  return LaunchReady(
    java: java,
    graph: graph,
    plan: assembleLaunchPlan(
      javaExecutable: java.path,
      jvmArgs: jvmArgs,
      gameArgs: gameArgs,
      mainClass: version.mainClass,
      workingDirectory: p.normalize(p.absolute(paths.root)),
      classpath: classpath,
      nativeArchives: [
        for (final a in graph.natives)
          p.normalize(p.absolute(paths.libraryFile(a.file.path))),
      ],
      separator: separator,
    ),
  );
}

String _absolute(GamePaths paths, String mavenPath) =>
    p.normalize(p.absolute(paths.libraryFile(mavenPath)));
