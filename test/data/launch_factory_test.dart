import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/instance/args.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/core/mc/arch_compat.dart';
import 'package:oh_my_mc/core/mc/host.dart';
import 'package:oh_my_mc/core/mc/install_plan.dart';
import 'package:oh_my_mc/core/mc/java_manager.dart';
import 'package:oh_my_mc/core/mc/launch_service.dart';
import 'package:oh_my_mc/core/account/account.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:path/path.dart' as p;

/// A version on disk, complete enough that `prepareLaunch` can read it.
///
/// Written as real JSON to a real temp directory: the factory's job is to read a
/// file, and a fake reader would not catch a wrong path.
Future<GamePaths> writeVersion(
  Directory root,
  String id, {
  int? javaMajor = 17,
  String type = 'release',
  bool withClientJar = true,
  bool withLibrary = true,
}) async {
  final paths = GamePaths(root.path);
  final dir = Directory(paths.versionDir(id));
  await dir.create(recursive: true);

  final json = <String, Object?>{
    'id': id,
    'type': type,
    'mainClass': 'net.minecraft.client.main.Main',
    'arguments': {
      'game': ['--username', r'${auth_player_name}'],
      'jvm': [
        '-Djava.library.path='
            r'${natives_directory}',
      ],
    },
    'libraries': [
      if (withLibrary)
        {
          'name': 'com.example:demo:1.0',
          'downloads': {
            'artifact': {
              'path': 'com/example/demo/1.0/demo-1.0.jar',
              'sha1': '',
              'size': 1,
              'url': 'https://example.invalid/demo.jar',
            },
          },
        },
    ],
    if (javaMajor != null) 'javaVersion': {'majorVersion': javaMajor},
    'assetIndex': {'id': id, 'sha1': '', 'size': 1, 'totalSize': 1},
    'assets': id,
    'downloads': {
      'client': {'sha1': '', 'size': 1, 'url': ''},
    },
  };
  await File(paths.versionJson(id)).writeAsString(jsonEncode(json));

  if (withClientJar) {
    await File(paths.versionJar(id)).writeAsString('jar');
  }
  if (withLibrary) {
    final lib = File(paths.libraryFile('com/example/demo/1.0/demo-1.0.jar'));
    await lib.create(recursive: true);
    await lib.writeAsString('jar');
  }
  return paths;
}

LauncherPaths pathsFor(Directory data, Directory game) =>
    LauncherPaths(data: data, game: game);

Instance instance({
  String id = 'demo',
  String versionId = '1.20.1',
  int? memoryMb,
  String? javaPath,
  IsolationKind isolation = IsolationKind.shareLibraries,
  List<String> jvmArgs = const [],
  List<String> gameArgs = const [],
  LoaderKind loader = LoaderKind.vanilla,
  String? loaderVersion,
}) => Instance(
  id: id,
  name: 'Demo',
  versionId: versionId,
  loader: loader,
  loaderVersion: loaderVersion,
  memoryMb: memoryMb,
  javaPath: javaPath,
  isolation: isolation,
  jvmArgs: jvmArgs,
  gameArgs: gameArgs,
);

/// A manager with one runtime, so no `java` process is probed.
JavaManager fakeJava(int major, {String path = '/fake/java/bin/java'}) =>
    JavaManager(
      hostOs: HostOs.linux,
      known: [
        JavaRuntime(
          path: path,
          majorVersion: major,
          versionString: '$major.0.0',
          vendor: 'test',
          arch: HostArch.x86_64,
        ),
      ],
    );

void main() {
  group('offlineUuid', () {
    test('matches the vanilla offline formula for a known name', () {
      // Values cross-checked against the output of the vanilla server's own
      // offline UUID derivation.
      expect(
        Account.offlineUuid('Notch'),
        'b50ad385-829d-3141-a216-7e7d7539ba7f',
      );
      expect(
        Account.offlineUuid('Player'),
        'a01e3843-e521-3998-958a-f459800e4d11',
      );
    });

    test('is a well-formed v3 UUID', () {
      final uuid = Account.offlineUuid('Anyone');
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-3[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
          r'[0-9a-f]{12}$',
        ).hasMatch(uuid),
        isTrue,
        reason: 'the server rejects a hash that is not version 3 / RFC variant',
      );
    });

    test('is stable and name-sensitive', () {
      expect(Account.offlineUuid('Alice'), Account.offlineUuid('Alice'));
      expect(Account.offlineUuid('Alice'), isNot(Account.offlineUuid('alice')));
    });
  });

  group('prepareInstanceLaunch', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('ommc-launch-');
    });

    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    test('a missing version is refused with the path it looked for', () async {
      final data = Directory(p.join(tmp.path, 'data'));
      final game = Directory(p.join(tmp.path, 'game'));
      await data.create(recursive: true);
      await game.create(recursive: true);
      final paths = pathsFor(data, game);
      const sameSettings = AppSettings.defaults;

      final outcome = await prepareInstanceLaunch(
        paths: paths,
        settings: sameSettings,
        instance: instance(versionId: 'not-installed'),
        javaManager: fakeJava(17),
      );

      expect(outcome, isA<LaunchRefused>());
      final blockers = (outcome as LaunchRefused).blockers;
      expect(blockers.single.code, BlockerCode.missingVersion);
      expect(blockers.single.message, contains('not-installed'));
      expect(blockers.single.remedy, isNotEmpty);
    });

    test('an unreadable version file is refused, not thrown', () async {
      final data = Directory(p.join(tmp.path, 'data'))
        ..createSync(recursive: true);
      final game = Directory(p.join(tmp.path, 'game'));
      final gamePaths = GamePaths(game.path);
      await Directory(gamePaths.versionDir('1.20.1')).create(recursive: true);
      await File(gamePaths.versionJson('1.20.1')).writeAsString('{ not json');
      final paths = pathsFor(data, game);
      const sameSettings = AppSettings.defaults;
      final outcome = await prepareInstanceLaunch(
        paths: paths,
        settings: sameSettings,
        instance: instance(),
        javaManager: fakeJava(17),
      );

      expect(outcome, isA<LaunchRefused>());
      expect(
        (outcome as LaunchRefused).blockers.single.code,
        BlockerCode.missingVersion,
      );
    });

    test('a complete install produces a runnable command', () async {
      final data = Directory(p.join(tmp.path, 'data'))
        ..createSync(recursive: true);
      final game = Directory(p.join(tmp.path, 'game'));
      await writeVersion(game, '1.20.1');
      final paths = pathsFor(data, game);
      const sameSettings = AppSettings.defaults;

      final outcome = await prepareInstanceLaunch(
        paths: paths,
        settings: sameSettings,
        instance: instance(memoryMb: 4096),
        javaManager: fakeJava(17),
      );

      expect(outcome, isA<LaunchReady>());
      final plan = (outcome as LaunchReady).plan;
      expect(plan.executable, contains('java'));
      expect(plan.args, contains('-Xmx4096M'));
      expect(
        plan.args.any((a) => a.startsWith('-Djava.library.path=')),
        isTrue,
        reason: 'a relative natives path makes LWJGL fail to load',
      );
      expect(
        plan.commandLine.any((a) => a.contains('--username')),
        isTrue,
        reason: 'offline launch must still pass a player name',
      );
    });

    test('the instance memory wins over the global setting', () async {
      final data = Directory(p.join(tmp.path, 'data'))
        ..createSync(recursive: true);
      final game = Directory(p.join(tmp.path, 'game'));
      await writeVersion(game, '1.20.1');
      final paths = pathsFor(data, game);
      const sameSettings = AppSettings(memoryMb: 2048);

      final withOverride = await prepareInstanceLaunch(
        paths: paths,
        settings: sameSettings,
        instance: instance(memoryMb: 8192),
        javaManager: fakeJava(17),
      );
      expect((withOverride as LaunchReady).plan.args, contains('-Xmx8192M'));

      final withoutOverride = await prepareInstanceLaunch(
        paths: paths,
        settings: sameSettings,
        instance: instance(),
        javaManager: fakeJava(17),
      );
      expect((withoutOverride as LaunchReady).plan.args, contains('-Xmx2048M'));
    });

    test('extra JVM args from the instance are applied', () async {
      final data = Directory(p.join(tmp.path, 'data'))
        ..createSync(recursive: true);
      final game = Directory(p.join(tmp.path, 'game'));
      await writeVersion(game, '1.20.1');
      final paths = pathsFor(data, game);
      const sameSettings = AppSettings.defaults;

      final outcome = await prepareInstanceLaunch(
        paths: paths,
        settings: sameSettings,
        instance: instance(jvmArgs: ['-XX:+UseG1GC']),
        javaManager: fakeJava(17),
      );

      expect((outcome as LaunchReady).plan.args, contains('-XX:+UseG1GC'));
    });

    test('arguments typed by the user reach argv as written', () async {
      final data = Directory(p.join(tmp.path, 'data'))
        ..createSync(recursive: true);
      final game = Directory(p.join(tmp.path, 'game'));
      await writeVersion(game, '1.20.1');
      final paths = pathsFor(data, game);

      // The whole path the user's typing takes: editor text, parser, store, argv.
      // A split in the wrong place here is a JVM rejection at launch, not a
      // cosmetic problem.
      final outcome = await prepareInstanceLaunch(
        paths: paths,
        settings: AppSettings.defaults,
        instance: instance(
          jvmArgs: parseArgs('-Dfoo="a b" -Xmx4G'),
          gameArgs: parseArgs('--fullscreen --server "my host"'),
        ),
        javaManager: fakeJava(17),
      );

      final args = (outcome as LaunchReady).plan.args;
      expect(args, contains('-Dfoo=a b'));
      expect(
        args,
        isNot(contains('b')),
        reason: 'the quoted part must not split',
      );
      expect(args, contains('-Xmx4G'));
      expect(args, contains('--server'));
      expect(
        args,
        contains('my host'),
        reason: 'a game argument with a space stays one entry',
      );
    });

    test('an isolated instance shares resources and owns its game directory', () async {
      final data = Directory(p.join(tmp.path, 'data'))
        ..createSync(recursive: true);
      final game = Directory(p.join(tmp.path, 'game'));
      // The installer writes to the shared tree even for an isolated instance:
      // libraries and assets are identical across instances, so only the game
      // directory moves. Reading the version from the instance tree instead is
      // what made every isolated instance look un-installed.
      await writeVersion(game, '1.20.1');
      final paths = pathsFor(data, game);
      const sameSettings = AppSettings.defaults;

      final outcome = await prepareInstanceLaunch(
        paths: paths,
        settings: sameSettings,
        instance: instance(isolation: IsolationKind.isolated),
        javaManager: fakeJava(17),
      );

      expect(outcome, isA<LaunchReady>());
      final plan = (outcome as LaunchReady).plan;
      expect(plan.workingDirectory, contains(p.join('instances', 'demo')));
      // ...and the classpath still comes from the shared install.
      expect(plan.classpath.join(' '), contains(game.path));
    });

    test('an isolated instance refuses when only its own tree has the version', () async {
      final data = Directory(p.join(tmp.path, 'data'))
        ..createSync(recursive: true);
      final game = Directory(p.join(tmp.path, 'game'))
        ..createSync(recursive: true);
      // A version dropped into the instance tree by hand is not an install: the
      // launcher never writes one there, and launching from it would skip the
      // shared libraries anyway.
      await writeVersion(
        Directory(p.join(data.path, 'instances', 'demo', 'minecraft')),
        '1.20.1',
      );
      final paths = pathsFor(data, game);

      final outcome = await prepareInstanceLaunch(
        paths: paths,
        settings: AppSettings.defaults,
        instance: instance(isolation: IsolationKind.isolated),
        javaManager: fakeJava(17),
      );

      expect(outcome, isA<LaunchRefused>());
    });

    test('a shared instance ignores the isolated tree and refuses', () async {
      final data = Directory(p.join(tmp.path, 'data'))
        ..createSync(recursive: true);
      final game = Directory(p.join(tmp.path, 'game'))
        ..createSync(recursive: true);
      await writeVersion(
        Directory(p.join(data.path, 'instances', 'demo', 'minecraft')),
        '1.20.1',
      );
      final paths = pathsFor(data, game);
      const sameSettings = AppSettings.defaults;

      final outcome = await prepareInstanceLaunch(
        paths: paths,
        settings: sameSettings,
        instance: instance(isolation: IsolationKind.shareLibraries),
        javaManager: fakeJava(17),
      );

      expect(outcome, isA<LaunchRefused>());
    });

    test('a missing client jar is reported as a missing file', () async {
      final data = Directory(p.join(tmp.path, 'data'))
        ..createSync(recursive: true);
      final game = Directory(p.join(tmp.path, 'game'));
      await writeVersion(game, '1.20.1', withClientJar: false);
      final paths = pathsFor(data, game);
      const sameSettings = AppSettings.defaults;

      final outcome = await prepareInstanceLaunch(
        paths: paths,
        settings: sameSettings,
        instance: instance(),
        javaManager: fakeJava(17),
      );

      expect(
        (outcome as LaunchRefused).blockers.map((b) => b.code),
        contains(BlockerCode.missingFiles),
      );
    });

    test('no Java runtime is refused with a download remedy', () async {
      final data = Directory(p.join(tmp.path, 'data'))
        ..createSync(recursive: true);
      final game = Directory(p.join(tmp.path, 'game'));
      await writeVersion(game, '1.20.1');
      final paths = pathsFor(data, game);
      const sameSettings = AppSettings.defaults;

      final outcome = await prepareInstanceLaunch(
        paths: paths,
        settings: sameSettings,
        instance: instance(),
        javaManager: JavaManager(hostOs: HostOs.linux),
      );

      final blocker = (outcome as LaunchRefused).blockers.firstWhere(
        (b) => b.code == BlockerCode.noRuntime,
      );
      expect(blocker.remedy, isNotEmpty);
    });

    test('a too-old runtime is refused, naming the required major', () async {
      final data = Directory(p.join(tmp.path, 'data'))
        ..createSync(recursive: true);
      final game = Directory(p.join(tmp.path, 'game'));
      await writeVersion(game, '1.20.1', javaMajor: 17);
      final paths = pathsFor(data, game);
      const sameSettings = AppSettings.defaults;

      final outcome = await prepareInstanceLaunch(
        paths: paths,
        settings: sameSettings,
        instance: instance(),
        javaManager: fakeJava(8),
      );

      final blockers = (outcome as LaunchRefused).blockers;
      expect(blockers.map((b) => b.code), contains(BlockerCode.javaTooOld));
      expect(
        blockers.any((b) => b.message.contains('17')),
        isTrue,
        reason: 'the message must name the version the user needs',
      );
    });

    test('pre-1.13 metadata with no javaVersion gets Java 8', () async {
      final data = Directory(p.join(tmp.path, 'data'))
        ..createSync(recursive: true);
      final game = Directory(p.join(tmp.path, 'game'));
      await writeVersion(game, '1.8.9', javaMajor: null);
      final paths = pathsFor(data, game);
      const sameSettings = AppSettings.defaults;

      final outcome = await prepareInstanceLaunch(
        paths: paths,
        settings: sameSettings,
        instance: instance(versionId: '1.8.9'),
        javaManager: fakeJava(8),
      );

      expect(
        outcome,
        isA<LaunchReady>(),
        reason:
            'no declared requirement must not mean "any Java", which would '
            'pick a Java 17 runtime that 1.8.9 cannot load',
      );
    });

    test('the player name from settings reaches the command', () async {
      final data = Directory(p.join(tmp.path, 'data'))
        ..createSync(recursive: true);
      final game = Directory(p.join(tmp.path, 'game'));
      await writeVersion(game, '1.20.1');
      final paths = pathsFor(data, game);
      const sameSettings = AppSettings(playerName: 'Steve_99');

      final outcome = await prepareInstanceLaunch(
        paths: paths,
        settings: sameSettings,
        instance: instance(),
        javaManager: fakeJava(17),
      );

      expect((outcome as LaunchReady).plan.args, contains('Steve_99'));
    });
  });
}
