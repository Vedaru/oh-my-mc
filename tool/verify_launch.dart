import 'dart:io';

import 'package:oh_my_mc/core/install/version_installer.dart';
import 'package:oh_my_mc/core/mc/host.dart';
import 'package:oh_my_mc/core/mc/install_plan.dart';
import 'package:oh_my_mc/core/mc/java_manager.dart';
import 'package:oh_my_mc/core/mc/launch_service.dart';

/// End-to-end proof that the argv this launcher builds is one a real JVM accepts.
///
/// Runs with a real JDK and a real installed version. The main class is swapped
/// for a stub that prints its arguments, because the real client would try to
/// open a window. Everything else in the command line is exactly what
/// [prepareLaunch] produced: real classpath, real natives dir, real flags.
// ignore_for_file: avoid_print
///
/// Usage: `dart run tool/verify_launch.dart <jdk-home> <minecraft-dir>`
Future<void> main(List<String> argv) async {
  if (argv.length < 2) {
    stderr.writeln('usage: verify_launch.dart <jdk-home> <minecraft-dir>');
    exit(2);
  }
  final jdkHome = argv[0];
  final root = argv[1];
  final paths = GamePaths(root);
  const versionId = '1.20.1';

  // 1. Install it for real.
  final installer = VersionInstaller(concurrency: 8);
  final install = await installer.install(
    versionId: versionId,
    paths: paths,
    host: const RuleContext(os: HostOs.linux, arch: HostArch.x86_64),
  );
  installer.close();
  stdout.writeln(
    'installed: ${install.plan.fileCount} files, '
    'verify complete=${install.verification.isComplete}',
  );

  // 2. Probe the JDK the same way the app does.
  final probe = JavaProbe(
    runProcess: (exe, args) async {
      final r = await Process.run(exe, args);
      return ProcessResultLike(
        exitCode: r.exitCode,
        stdout: '${r.stdout}',
        stderr: '${r.stderr}',
      );
    },
  );
  final java = await probe.probe('$jdkHome/bin/java');
  if (java == null) {
    stderr.writeln('could not probe the JDK at $jdkHome');
    exit(1);
  }
  stdout.writeln('probed: $java');

  // 3. A stub main class that prints the arguments it was given.
  final stubDir = Directory('${root}_stub')..createSync(recursive: true);
  File('${stubDir.path}/Stub.java').writeAsStringSync('''
public class Stub {
  public static void main(String[] args) {
    System.out.println("STUB_ARGV_BEGIN");
    for (String a : args) System.out.println(a);
    System.out.println("STUB_ARGV_END");
  }
}
''');
  final javac = await Process.run('$jdkHome/bin/javac', [
    '-d',
    stubDir.path,
    '${stubDir.path}/Stub.java',
  ]);
  if (javac.exitCode != 0) {
    stderr.writeln('javac failed: ${javac.stderr}');
    exit(1);
  }

  // 4. Build the launch exactly as the app would, then point it at the stub.
  final version = install.version;
  final outcome = prepareLaunch(
    version: version,
    paths: paths,
    host: const RuleContext(os: HostOs.linux, arch: HostArch.x86_64),
    request: const LaunchRequest(
      versionId: versionId,
      playerName: 'Steve',
      uuid: '00000000000000000000000000000000',
      accessToken: 'not-a-real-token',
    ),
    java: java,
  );
  if (outcome is! LaunchReady) {
    stderr.writeln('launch refused: $outcome');
    exit(1);
  }
  final plan = outcome.plan;
  stdout.writeln('argv length: ${plan.args.length}');

  // Keep every JVM flag, replace the main class with the stub. The classpath
  // also gets the stub dir so java can load it.
  final mainIdx = plan.args.indexOf(plan.mainClass);
  final realClasspath = plan.args[plan.args.indexOf('-cp') + 1];
  final stubClasspath = '${stubDir.path}:$realClasspath';

  final runArgs = [
    for (var i = 0; i < plan.args.length; i++)
      if (i == mainIdx)
        'Stub'
      else if (i == plan.args.indexOf('-cp') + 1)
        stubClasspath
      else
        plan.args[i],
    // The real client args follow the stub's class name; keep them so the JVM
    // has to accept them too (an unknown flag would fail here).
  ];

  final result = await Process.run(plan.executable, runArgs);
  stdout.write(result.stdout);
  stderr.write(result.stderr);

  final out = '${result.stdout}';
  if (!out.contains('STUB_ARGV_BEGIN')) {
    stderr.writeln('the stub never ran - the JVM rejected the command line');
    exit(1);
  }

  // 5. Assert the things that were actually broken before.
  final lines = out
      .split('\n')
      .skipWhile((l) => !l.contains('STUB_ARGV_BEGIN'))
      .skip(1)
      .takeWhile((l) => !l.contains('STUB_ARGV_END'))
      .toList();

  final failures = <String>[];
  void check(bool ok, String what) {
    stdout.writeln('  ${ok ? "ok  " : "FAIL"} $what');
    if (!ok) failures.add(what);
  }

  // JVM flags are consumed by the JVM and must NOT appear in the game's argv,
  // so they are asserted against the command line, not the stub's output.
  check(
    plan.args.any((a) => a.startsWith('-Djava.library.path=')),
    'JVM was given -Djava.library.path',
  );
  check(
    plan.args.any((a) => a.contains('/natives')),
    'natives path points at the natives dir',
  );
  final log4jArg = plan.args.firstWhere(
    (a) => a.startsWith('-Dlog4j.configurationFile='),
    orElse: () => '',
  );
  check(log4jArg.endsWith('.xml'), 'log4j points at a file, not a directory');
  check(
    log4jArg.isNotEmpty && File(log4jArg.split('=').last).existsSync(),
    'the log4j config file exists on disk',
  );
  check(
    lines.length > 20,
    'the full game argument list reached the JVM (${lines.length} args)',
  );
  check(
    !lines.any((l) => l.contains(r'${')),
    'no unexpanded placeholder survived',
  );
  check(lines.any((l) => l.contains('--username')), 'username is present');
  check(result.exitCode == 0, 'JVM exited 0 (got ${result.exitCode})');

  // 6. The classpath must be fully absolute and the client jar must be on it.
  final cp = realClasspath.split(':');
  check(
    cp.every((e) => e.startsWith('/')),
    'every classpath entry is absolute',
  );
  check(
    cp.any((e) => e.endsWith('/versions/1.20.1/1.20.1.jar')),
    'the client jar is on the classpath',
  );
  check(
    cp.every((e) => File(e).existsSync()),
    'every classpath entry exists on disk (${cp.length} entries)',
  );

  stdout.writeln(
    failures.isEmpty ? '\nLAUNCH VERIFIED' : '\n${failures.length} FAILURES',
  );
  exit(failures.isEmpty ? 0 : 1);
}
