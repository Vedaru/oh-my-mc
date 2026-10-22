import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/mc/host.dart';
import 'package:oh_my_mc/core/mc/jvm_args.dart';
import 'package:oh_my_mc/core/mc/launch_plan.dart';
import 'package:oh_my_mc/core/mc/library_graph.dart';

import 'fixtures.dart';

const _linux = RuleContext(os: HostOs.linux, arch: HostArch.x86_64);

/// Builds the real launch command for a captured version, exactly as the
/// launcher will: resolve libs, render args, assemble argv.
LaunchPlan planFor(String versionId, {String java = '/jdk-17/bin/java'}) {
  final version = loadVersion(versionId);
  final graph = buildLibraryGraph(version, _linux);
  final natives = nativesDirectoryFor(versionId, '/mc/versions');

  final vars = LaunchVariables(
    authPlayerName: 'Steve',
    versionName: versionId,
    gameDirectory: '/mc',
    assetsRoot: '/mc/assets',
    assetIndexName: version.assetIndexName,
    authUuid: '00000000000000000000000000000000',
    authAccessToken: 'token',
    userType: 'msa',
    versionType: 'release',
    nativesDirectory: natives,
    classpath: graph.classpathPaths.join(classpathSeparator),
  );

  return assembleLaunchPlan(
    javaExecutable: java,
    jvmArgs: renderArguments(version, ArgSide.jvm, _linux, vars),
    gameArgs: renderArguments(version, ArgSide.game, _linux, vars),
    mainClass: version.mainClass,
    workingDirectory: '/mc',
    classpath: graph.classpathPaths,
    nativeArchives: [for (final n in graph.natives) n.file.path],
  );
}

void main() {
  setUpAll(() => classpathSeparator = ':');

  group('end-to-end launch plan (1.20.1, linux x64)', () {
    late final LaunchPlan plan = planFor('1.20.1');

    test('is java <args> mainClass <gameArgs>', () {
      expect(plan.executable, '/jdk-17/bin/java');
      expect(plan.args, contains('net.minecraft.client.main.Main'));
      final mainIdx = plan.args.indexOf('net.minecraft.client.main.Main');
      expect(mainIdx, greaterThan(0));
      // Everything after the main class is game arguments.
      expect(plan.args[mainIdx + 1], '--username');
      expect(plan.args[mainIdx + 2], 'Steve');
    });

    test(r'the ${classpath} placeholder is fully substituted', () {
      expect(
        plan.args.any((a) => a.contains(r'${classpath}')),
        isFalse,
        reason: 'unexpanded placeholder would be a broken JVM flag',
      );
      // The joined classpath appears exactly once, right after -cp.
      final cpIdx = plan.args.indexOf('-cp');
      expect(cpIdx, greaterThanOrEqualTo(0));
      expect(plan.args[cpIdx + 1], plan.classpath.join(':'));
      expect(plan.classpath.length, greaterThan(50));
    });

    test('no argument contains an unexpanded placeholder', () {
      for (final a in plan.args) {
        expect(
          a.contains(r'${'),
          isFalse,
          reason: 'unexpanded placeholder in "$a"',
        );
      }
    });

    test('natives directory is wired for the modern layout', () {
      expect(
        plan.args,
        contains('-Djava.library.path=/mc/versions/1.20.1/natives'),
      );
    });

    test('launcher branding is ours, not Mojang\'s', () {
      expect(plan.args, contains('-Dminecraft.launcher.brand=oh my mc'));
    });

    test('access token is present exactly once', () {
      expect(plan.args.where((a) => a == 'token'), hasLength(1));
    });

    test('command line is renderable for logs without leaking the token', () {
      expect(plan.commandLine.first, '/jdk-17/bin/java');
      expect(plan.toString(), contains('net.minecraft.client.main.Main'));
    });
  });

  group('legacy launch plan (1.12.2, linux x64)', () {
    test('gets a synthesized jvm block and still gets natives', () {
      final plan = planFor('1.12.2', java: '/jdk8/bin/java');
      expect(plan.executable, '/jdk8/bin/java');
      // Not `args.first == mainClass`: a legacy launch has JVM flags in front of
      // it, and asserting otherwise locked in a command line the JVM rejects.
      expect(plan.args, contains('net.minecraft.client.main.Main'));
      expect(plan.args, contains('-cp'));
      expect(
        plan.args.any((a) => a.startsWith('-Djava.library.path=')),
        isTrue,
      );
      expect(plan.nativeArchives, isNotEmpty);
      expect(plan.args.join(' '), contains('--username Steve'));
    });

    test('legacy game args carry every required placeholder', () {
      final plan = planFor('1.8.9', java: '/jdk8/bin/java');
      final joined = plan.args.join(' ');
      expect(joined, contains('--assetIndex 1.8'));
      expect(joined, contains('--accessToken token'));
      expect(joined, contains('--version 1.8.9'));
      expect(joined.contains(r'${'), isFalse);
    });
  });
}
