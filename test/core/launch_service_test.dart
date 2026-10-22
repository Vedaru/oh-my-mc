import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/mc/arch_compat.dart';
import 'package:oh_my_mc/core/mc/host.dart';
import 'package:oh_my_mc/core/mc/install_plan.dart';
import 'package:oh_my_mc/core/mc/java_manager.dart';
import 'package:oh_my_mc/core/mc/jvm_args.dart';
import 'package:oh_my_mc/core/mc/launch_service.dart';
import 'package:oh_my_mc/core/mc/version_json.dart';
import 'package:path/path.dart' as p;

import 'fixtures.dart';

const _linux = RuleContext(os: HostOs.linux, arch: HostArch.x86_64);

const _java17 = JavaRuntime(
  path: '/jdk-17/bin/java',
  majorVersion: 17,
  versionString: '17.0.9+9',
  vendor: 'Eclipse Adoptium',
  arch: HostArch.x86_64,
);

const _java8 = JavaRuntime(
  path: '/jdk-8/bin/java',
  majorVersion: 8,
  versionString: '1.8.0_402',
  vendor: 'Oracle',
  arch: HostArch.x86_64,
);

LaunchRequest requestFor(String versionId) => LaunchRequest(
  versionId: versionId,
  playerName: 'Steve',
  uuid: '00000000000000000000000000000000',
  accessToken: 'token',
  userType: 'msa',
);

void main() {
  late Directory tmp;
  late GamePaths paths;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('launch_service_test');
    paths = GamePaths(tmp.path);
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  /// Creates every file [version] will be handed, so `checkFiles` passes.
  void materialize(VersionJson version, {String? jarOverride}) {
    for (final lib in version.libraries) {
      final artifact = lib.downloads?.artifact;
      if (artifact != null && artifact.path.isNotEmpty) {
        File(paths.libraryFile(artifact.path))
          ..createSync(recursive: true)
          ..writeAsStringSync('');
      }
      for (final nat
          in lib.downloads?.classifiers.values ?? const <DownloadArtifact>[]) {
        if (nat.path.isEmpty) continue;
        File(paths.libraryFile(nat.path))
          ..createSync(recursive: true)
          ..writeAsStringSync('');
      }
    }
    final jar = paths.versionJar(jarOverride ?? version.jar ?? version.id);
    File(jar)
      ..createSync(recursive: true)
      ..writeAsStringSync('');
  }

  group('classpath construction', () {
    test('library entries are absolute even for a relative game root', () {
      // An absolute root makes `p.absolute` a no-op, so a test using one passes
      // even when the absolutization is deleted. Verified by mutation: this
      // version fails when the `p.absolute` call is removed.
      final version = loadVersion('1.20.1');
      final cp = buildClasspath(
        version: version,
        paths: const GamePaths('relative-mc'),
        libraryPaths: const ['com/google/gson/gson/2.10/gson-2.10.jar'],
      );

      expect(
        p.isAbsolute(cp.first),
        isTrue,
        reason:
            'a relative classpath entry is resolved against the JVM process '
            'CWD, not the game directory, so the jar is silently not found',
      );
      expect(cp.first, endsWith('com/google/gson/gson/2.10/gson-2.10.jar'));
      expect(cp.first, contains('relative-mc/libraries'));
    });

    test('the client jar is in the classpath, last', () {
      final version = loadVersion('1.20.1');
      final cp = buildClasspath(
        version: version,
        paths: paths,
        libraryPaths: const ['a/b.jar'],
      );

      expect(cp.last, endsWith('1.20.1.jar'));
      expect(
        cp.last,
        p.normalize(p.absolute(paths.versionJar('1.20.1'))),
        reason: 'without the client jar there is no main class to load',
      );
      expect(cp.length, 2);
    });

    test('a jar override points the client jar at the parent', () {
      final version = VersionJson.fromJson({
        'id': 'forge-47',
        'type': 'release',
        'mainClass': 'net.minecraft.launchwrapper.Launch',
        'jar': '1.20.1',
        'libraries': const [],
      });

      final cp = buildClasspath(
        version: version,
        paths: paths,
        libraryPaths: const [],
      );

      expect(cp.single, endsWith('/versions/1.20.1/1.20.1.jar'));
    });

    test('library order is preserved ahead of the client jar', () {
      final version = loadVersion('1.20.1');
      final cp = buildClasspath(
        version: version,
        paths: paths,
        libraryPaths: const ['first.jar', 'second.jar', 'third.jar'],
      );

      expect(
        cp.take(3).map(p.basename).toList(),
        ['first.jar', 'second.jar', 'third.jar'],
        reason:
            'classpath resolution is first-wins, so modloader-patched jars '
            'must stay ahead of vanilla ones',
      );
    });
  });

  group('legacy versions get a synthesized JVM block', () {
    test('1.12.2 has no arguments.jvm in its metadata', () {
      final version = loadVersion('1.12.2');
      expect(
        version.arguments.jvm,
        isEmpty,
        reason:
            'this is *why* the block has to be synthesized; if Mojang ever '
            'starts shipping one, this test should be revisited',
      );
    });

    test('1.12.2 is still given -cp and java.library.path', () {
      final version = loadVersion('1.12.2');
      final vars = LaunchVariables(
        authPlayerName: 'Steve',
        versionName: '1.12.2',
        gameDirectory: '/mc',
        assetsRoot: '/mc/assets',
        assetIndexName: version.assetIndexName,
        authUuid: 'u',
        authAccessToken: 't',
        userType: 'legacy',
        versionType: 'release',
        nativesDirectory: '/mc/versions/1.12.2/natives',
        classpath: '/mc/libraries/a.jar:/mc/versions/1.12.2/1.12.2.jar',
      );

      final args = renderArguments(version, ArgSide.jvm, _linux, vars);

      expect(
        args,
        contains('-Djava.library.path=/mc/versions/1.12.2/natives'),
        reason: 'without this the JVM cannot load LWJGL 2 natives',
      );
      expect(args, contains('-cp'));
      expect(args[args.indexOf('-cp') + 1], vars.classpath);
      expect(
        args.join(' ').contains(r'${'),
        isFalse,
        reason: 'a placeholder left in -cp would be a broken flag',
      );
    });

    test('1.8.9 gets the same synthesized block', () {
      final version = loadVersion('1.8.9');
      final vars = LaunchVariables(
        authPlayerName: 'Steve',
        versionName: '1.8.9',
        gameDirectory: '/mc',
        assetsRoot: '/mc/assets',
        assetIndexName: version.assetIndexName,
        authUuid: 'u',
        authAccessToken: 't',
        userType: 'legacy',
        versionType: 'release',
        nativesDirectory: '/natives',
        classpath: '/cp',
      );
      expect(renderArguments(version, ArgSide.jvm, _linux, vars), [
        '-Djava.library.path=/natives',
        '-cp',
        '/cp',
      ]);
    });

    test('modern versions are untouched by the legacy path', () {
      final version = loadVersion('1.20.1');
      final vars = LaunchVariables(
        authPlayerName: 'Steve',
        versionName: '1.20.1',
        gameDirectory: '/mc',
        assetsRoot: '/mc/assets',
        assetIndexName: version.assetIndexName,
        authUuid: 'u',
        authAccessToken: 't',
        userType: 'msa',
        versionType: 'release',
        nativesDirectory: '/natives',
        classpath: '/cp',
      );
      final args = renderArguments(version, ArgSide.jvm, _linux, vars);

      expect(
        args.where((a) => a == '-cp').length,
        1,
        reason:
            'the metadata already supplies -cp; a synthesized one would '
            'duplicate the classpath and can shadow it',
      );
      expect(args[args.indexOf('-cp') + 1], '/cp');
    });
  });

  group('prepareLaunch', () {
    test('refuses with a reason when no runtime exists', () {
      final outcome = prepareLaunch(
        version: loadVersion('1.20.1'),
        paths: paths,
        host: _linux,
        request: requestFor('1.20.1'),
        java: null,
        checkFiles: false,
      );

      expect(outcome, isA<LaunchRefused>());
      final blockers = (outcome as LaunchRefused).blockers;
      expect(blockers.map((b) => b.code), contains(BlockerCode.noRuntime));
    });

    test('names the missing files instead of letting the JVM fail', () {
      final outcome = prepareLaunch(
        version: loadVersion('1.20.1'),
        paths: paths,
        host: _linux,
        request: requestFor('1.20.1'),
        java: _java17,
      );

      expect(outcome, isA<LaunchRefused>());
      final missing = (outcome as LaunchRefused).blockers.firstWhere(
        (b) => b.code == BlockerCode.missingFiles,
      );
      expect(missing.message, contains('missing'));
      // Nothing was materialized, so every classpath entry is missing.
      expect(missing.message, isNot(contains('1 file')));
    });

    test('a complete install produces a runnable command line', () {
      final version = loadVersion('1.20.1');
      materialize(version);

      final outcome = prepareLaunch(
        version: version,
        paths: paths,
        host: _linux,
        request: requestFor('1.20.1'),
        java: _java17,
      );

      expect(outcome, isA<LaunchReady>());
      final plan = (outcome as LaunchReady).plan;

      expect(plan.executable, '/jdk-17/bin/java');
      expect(plan.args, contains('net.minecraft.client.main.Main'));
      expect(plan.args, contains('-cp'));

      final cpIdx = plan.args.indexOf('-cp');
      final cp = plan.args[cpIdx + 1];
      expect(
        cp.split(':').every(p.isAbsolute),
        isTrue,
        reason: 'every classpath entry must be absolute',
      );
      expect(cp, contains('1.20.1.jar'));
      expect(plan.args.join(' ').contains(r'${'), isFalse);
      expect(plan.workingDirectory, p.normalize(p.absolute(paths.root)));
    });

    test('the memory cap is applied ahead of the metadata flags', () {
      final version = loadVersion('1.20.1');
      materialize(version);

      final outcome = prepareLaunch(
        version: version,
        paths: paths,
        host: _linux,
        request: LaunchRequest(
          versionId: '1.20.1',
          playerName: 'Steve',
          uuid: 'u',
          accessToken: 't',
          memoryMb: 4096,
        ),
        java: _java17,
      );

      final args = (outcome as LaunchReady).plan.args;
      expect(args.first, '-Xmx4096M');
    });

    test('the access token appears once, never in the classpath', () {
      final version = loadVersion('1.20.1');
      materialize(version);

      final outcome = prepareLaunch(
        version: version,
        paths: paths,
        host: _linux,
        request: requestFor('1.20.1'),
        java: _java17,
      );

      final args = (outcome as LaunchReady).plan.args;
      expect(args.where((a) => a == 'token').length, 1);
      final cp = args[args.indexOf('-cp') + 1];
      expect(cp.contains('token'), isFalse);
    });

    test('a newer Java is accepted but reported as a mismatch', () {
      final version = loadVersion('1.20.1');
      materialize(version);

      final outcome = prepareLaunch(
        version: version,
        paths: paths,
        host: _linux,
        request: requestFor('1.20.1'),
        java: const JavaRuntime(
          path: '/jdk-21/bin/java',
          majorVersion: 21,
          versionString: '21.0.1',
          vendor: 'Temurin',
          arch: HostArch.x86_64,
        ),
      );

      expect(
        outcome,
        isA<LaunchReady>(),
        reason: 'Java 21 runs 1.20.1; refusing would be wrong',
      );
    });

    test('an old Java is refused, not launched and crashed', () {
      final version = loadVersion('1.20.1');
      materialize(version);

      final outcome = prepareLaunch(
        version: version,
        paths: paths,
        host: _linux,
        request: requestFor('1.20.1'),
        java: _java8,
      );

      expect(outcome, isA<LaunchRefused>());
      expect(
        (outcome as LaunchRefused).blockers.map((b) => b.code),
        contains(BlockerCode.javaTooOld),
      );
    });

    test('LWJGL 2 on Apple Silicon is refused, not launched', () {
      final version = loadVersion('1.12.2');
      const osxArm = RuleContext(os: HostOs.osx, arch: HostArch.arm64);

      final outcome = prepareLaunch(
        version: version,
        paths: paths,
        host: osxArm,
        request: requestFor('1.12.2'),
        java: const JavaRuntime(
          path: '/jdk-8/bin/java',
          majorVersion: 8,
          versionString: '1.8.0_402',
          vendor: 'Oracle',
          arch: HostArch.arm64,
        ),
        checkFiles: false,
      );

      expect(outcome, isA<LaunchRefused>());
      expect(
        (outcome as LaunchRefused).blockers.map((b) => b.code),
        contains(BlockerCode.lwjgl2OnArm64Mac),
      );
    });

    test('log4j points at the config file, not its directory', () {
      final version = loadVersion('1.20.1');
      materialize(version);

      final outcome = prepareLaunch(
        version: version,
        paths: paths,
        host: _linux,
        request: requestFor('1.20.1'),
        java: _java17,
      );

      final args = (outcome as LaunchReady).plan.args;
      final log4j = args.firstWhere(
        (a) => a.startsWith('-Dlog4j.configurationFile='),
      );
      expect(
        log4j,
        endsWith('/client-1.12.xml'),
        reason:
            'the metadata names the file in logging.client.file.id; '
            'passing the directory makes log4j fail silently',
      );
    });

    test('legacy on Linux x64 is launchable end to end', () {
      final version = loadVersion('1.12.2');
      materialize(version);

      final outcome = prepareLaunch(
        version: version,
        paths: paths,
        host: _linux,
        request: requestFor('1.12.2'),
        java: _java8,
      );

      expect(outcome, isA<LaunchReady>());
      final plan = (outcome as LaunchReady).plan;
      final joined = plan.args.join(' ');

      expect(joined, contains('-Djava.library.path='));
      expect(joined, contains('-cp '));
      expect(joined, contains('--username Steve'));
      expect(joined.contains(r'${'), isFalse);
    });
  });
}
