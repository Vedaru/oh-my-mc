import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../app/providers.dart';
import '../core/instance/instance.dart';
import '../core/mc/arch_compat.dart';
import '../core/launch/launch_handle.dart';
import '../core/mc/host.dart';
import '../core/mc/install_plan.dart';
import '../core/mc/java_manager.dart';
import '../core/mc/java_provisioner.dart';
import '../core/mc/local_host.dart';
import '../core/mc/launch_service.dart';
import '../core/mc/version_json.dart';
import 'settings.dart';

/// Where the launcher keeps everything. One object so a test can point the whole
/// app at a temporary directory.
class LauncherPaths {
  const LauncherPaths({required this.data, required this.game});

  /// Settings, the instance file, managed Java runtimes.
  final Directory data;

  /// The `.minecraft`-equivalent tree.
  final Directory game;

  GamePaths get gamePaths => GamePaths(game.path);

  /// Every instance directory lives here. Exposed so deletion can check it is
  /// staying inside it instead of trusting a stored id.
  Directory get instanceRoot => Directory(p.join(data.path, 'instances'));

  /// One instance's own directory, under `<data>/instances/<id>`.
  Directory instanceDir(String id) => Directory(p.join(instanceRoot.path, id));

  /// The `minecraft` tree an instance actually launches against.
  ///
  /// A shared instance uses the global `game` directory directly. An isolated
  /// one gets its own `minecraft/` inside its instance directory, which is what
  /// makes two instances see different mods for the same version.
  GamePaths gamePathsFor(Instance instance) =>
      instance.isolation == IsolationKind.isolated
      ? GamePaths(p.join(instanceDir(instance.id).path, 'minecraft'))
      : gamePaths;
}

final launcherPathsProvider = Provider<LauncherPaths>(
  (ref) => throw StateError('launcherPathsProvider must be overridden'),
);

/// The real launch handle factory.
///
/// Its whole job is to turn an [Instance] plus settings into the `prepare`
/// callback [ProcessLaunchHandle] runs. The work is deliberately *inside*
/// `prepare` rather than before the handle is created: reading and resolving a
/// version, scanning JVMs and building a classpath all take real time, and doing
/// them there is what lets the UI show `preparing` instead of freezing.
LaunchHandle Function(Instance) realLaunchHandleFactory(Ref ref) {
  return (instance) {
    // Read once, at launch time: the user may have changed the player name or
    // memory since the screen was built, and a launch should use what is on
    // screen now rather than what was on screen when the shell was created.
    final paths = ref.read(launcherPathsProvider);
    final settings = ref.read(appSettingsProvider);
    return ProcessLaunchHandle(
      prepare: () => prepareInstanceLaunch(
        instance: instance,
        paths: paths,
        settings: settings,
      ),
    );
  };
}

/// Builds the command for [instance], or explains why it cannot be built.
Future<LaunchOutcome> prepareInstanceLaunch({
  required Instance instance,
  required LauncherPaths paths,
  required AppSettings settings,
  JavaManager? javaManager,
  RuleContext? host,
}) async {
  final gamePaths = paths.gamePathsFor(instance);

  final versionFile = File(gamePaths.versionJson(instance.versionId));
  if (!await versionFile.exists()) {
    return LaunchRefused([
      LaunchBlocker(
        code: BlockerCode.missingVersion,
        message:
            'Version ${instance.versionId} is not installed yet '
            '(expected ${versionFile.path}).',
        remedy: 'Install it from the Download screen first.',
      ),
    ]);
  }

  final VersionJson version;
  try {
    final raw = jsonDecode(await versionFile.readAsString());
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('version json is not an object');
    }
    version = VersionJson.fromJson(raw);
  } on Object catch (e) {
    // A truncated or hand-edited version file is the user's problem to see, not
    // a stack trace to swallow.
    return LaunchRefused([
      LaunchBlocker(
        code: BlockerCode.missingVersion,
        message: 'Version ${instance.versionId} could not be read: $e',
        remedy: 'Reinstall the version from the Download screen.',
      ),
    ]);
  }

  // A supplied manager is trusted as-is: it is already scanned (or deliberately
  // has nothing), and scanning again would reach into the real machine during a
  // test. Only the internally built one needs a scan.
  var manager = javaManager;
  if (manager == null) {
    manager = JavaManager(hostOs: localHostOs, known: const []);
    await manager.scan(
      javaHome: instance.javaPath == null
          ? Platform.environment['JAVA_HOME']
          : p.dirname(p.dirname(instance.javaPath!)),
      // Runtimes the launcher downloaded itself. Without this a managed JRE is
      // invisible to the launch path, which is the whole point of shipping one.
      managedRoots: managedJavaExecutables(paths.data),
    );
  }

  final JavaRuntime? java = instance.javaPath != null
      ? _runtimeAt(manager.runtimes, instance.javaPath!)
      : _selectFor(manager.runtimes, version);

  return prepareLaunch(
    version: version,
    paths: gamePaths,
    host: host ?? localRuleContext(),
    request: buildLaunchRequest(
      instance: instance,
      settings: settings,
      version: version,
    ),
    java: java,
  );
}

/// The request a launch is built from, isolated so the argv it produces is
/// assertable without a JVM or a version tree.
LaunchRequest buildLaunchRequest({
  required Instance instance,
  required AppSettings settings,
  required VersionJson version,
}) => LaunchRequest(
  versionId: version.jar ?? version.id,
  playerName: settings.playerName,
  // Offline mode: the UUID is derived from the name the way the game does it
  // offline (`OfflinePlayer:<name>`), so worlds and inventories stay stable
  // across launcher restarts. Microsoft sign-in replaces both later.
  uuid: offlineUuid(settings.playerName),
  accessToken: '0',
  versionType: version.type,
  memoryMb: instance.memoryMb ?? settings.memoryMb,
  extraJvmArgs: instance.jvmArgs,
  extraGameArgs: [
    ...instance.gameArgs,
    // Window size as command-line flags rather than the version JSON's
    // `has_custom_resolution` branch: those args are gated behind a feature flag
    // and carry `${resolution_width}` placeholders, and passing both would send
    // `--width` twice.
    if (instance.windowWidth != null && instance.windowHeight != null) ...[
      '--width',
      '${instance.windowWidth}',
      '--height',
      '${instance.windowHeight}',
    ],
    if (instance.fullscreen) '--fullscreen',
  ],
);

JavaRuntime? _runtimeAt(List<JavaRuntime> runtimes, String path) {
  final normalized = p.normalize(p.absolute(path));
  for (final runtime in runtimes) {
    if (p.normalize(p.absolute(runtime.path)) == normalized) return runtime;
  }
  return null;
}

JavaRuntime? _selectFor(List<JavaRuntime> runtimes, VersionJson version) {
  final required = version.javaVersion?.majorVersion;
  // No declared requirement is pre-1.13 metadata, which needs Java 8 semantics
  // but runs on 8; guessing 8 is what the game itself assumes.
  if (required == null) {
    return selectRuntime(runtimes, 8) ?? _lowest(runtimes);
  }
  // Fall back to the highest runtime rather than `null` when nothing is new
  // enough: `checkJava` then reports "Java 8 is too old, needs 17", which is
  // actionable. Returning null here would collapse that into "no Java at all" -
  // true of the *requirement*, false of the machine, and unfixable by the user.
  return selectRuntime(runtimes, required) ?? _highest(runtimes);
}

JavaRuntime? _highest(List<JavaRuntime> runtimes) {
  if (runtimes.isEmpty) return null;
  final sorted = [...runtimes]
    ..sort((a, b) => b.majorVersion.compareTo(a.majorVersion));
  return sorted.first;
}

JavaRuntime? _lowest(List<JavaRuntime> runtimes) {
  if (runtimes.isEmpty) return null;
  final sorted = [...runtimes]
    ..sort((a, b) => a.majorVersion.compareTo(b.majorVersion));
  return sorted.first;
}

/// The offline UUID every launcher and the vanilla server agree on.
///
/// Derived with `crypto`'s MD5 rather than a hand-rolled implementation: this is
/// the one hash in the app, and a subtly wrong one would silently give the user
/// a different identity on every server.
String offlineUuid(String name) {
  final hash = md5.convert(utf8.encode('OfflinePlayer:$name')).bytes;
  final chars = [
    for (final byte in hash)
      ...byte.toRadixString(16).padLeft(2, '0').split(''),
  ];
  // Bytes 6 and 8 hold the version and variant nibbles, so patch the hex digit
  // at char 12 and 16. Splicing strings is what got this wrong the first time.
  chars[12] = '3';
  chars[16] = ((int.parse(chars[16], radix: 16) & 0x3) | 0x8).toRadixString(16);
  final hex = chars.join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
