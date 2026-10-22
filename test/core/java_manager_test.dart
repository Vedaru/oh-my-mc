import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/mc/host.dart';
import 'package:oh_my_mc/core/mc/java_manager.dart';

/// Real `java -XshowSettings:properties -version` output shapes.
const _jdk17Output = '''
Property settings:
    java.home = /usr/lib/jvm/java-17-openjdk-amd64
    java.vendor = Eclipse Adoptium
    java.vendor.url = https://adoptium.net/
    java.version = 17.0.9
    java.vm.name = OpenJDK 64-Bit Server VM
    os.arch = amd64
    os.name = Linux

openjdk version "17.0.9" 2023-10-17
OpenJDK Runtime Environment Temurin-17.0.9+9 (build 17.0.9+9)
''';

const _jdk8Output = '''
Property settings:
    java.home = /Library/Java/JavaVirtualMachines/zulu-8.jdk/Contents/Home
    java.vendor = Azul Systems, Inc.
    java.version = 1.8.0_402
    os.arch = aarch64
    os.name = Darwin

openjdk version "1.8.0_402"
''';

const _jdk25Output = '''
Property settings:
    java.version = 25
    java.vendor = Oracle Corporation
    os.arch = x86_64
''';

void main() {
  group('major version parsing', () {
    test('legacy 1.x form', () {
      expect(JavaProbe.majorFromVersionString('1.8.0_402'), 8);
      expect(JavaProbe.majorFromVersionString('1.7.0_80'), 7);
    });

    test('modern form', () {
      expect(JavaProbe.majorFromVersionString('17.0.9'), 17);
      expect(JavaProbe.majorFromVersionString('21.0.1+12'), 21);
      expect(JavaProbe.majorFromVersionString('25'), 25);
    });

    test('early-access suffix', () {
      expect(JavaProbe.majorFromVersionString('25-ea'), 25);
    });

    test('garbage is 0, not a crash', () {
      expect(JavaProbe.majorFromVersionString(''), 0);
      expect(JavaProbe.majorFromVersionString('not-a-version'), 0);
    });
  });

  group('property dump parsing', () {
    test('extracts only java.* and os.* keys', () {
      final props = JavaProbe.parseProperties(_jdk17Output);
      expect(props['java.version'], '17.0.9');
      expect(props['java.vendor'], 'Eclipse Adoptium');
      expect(props['os.arch'], 'amd64');
      expect(
        props.keys.every((k) => k.startsWith('java.') || k.startsWith('os.')),
        isTrue,
      );
      expect(props.containsKey('openjdk version "17.0.9" 2023-10-17'), isFalse);
    });

    test('full runtime is derived from the dump', () {
      final runtime = JavaProbe.parseExecutableOutput(
        '/x/bin/java',
        _jdk17Output,
      )!;
      expect(runtime.majorVersion, 17);
      expect(runtime.arch, HostArch.x86_64);
      expect(runtime.vendor, 'Eclipse Adoptium');
      expect(runtime.is64Bit, isTrue);
      expect(runtime.path, '/x/bin/java');
    });

    test('arm64 is detected from os.arch', () {
      final runtime = JavaProbe.parseExecutableOutput(
        '/mac/java',
        _jdk8Output,
      )!;
      expect(runtime.arch, HostArch.arm64);
      expect(runtime.majorVersion, 8);
      expect(runtime.vendor, 'Azul Systems, Inc.');
    });

    test('a dump with no version is not a runtime', () {
      expect(JavaProbe.parseExecutableOutput('/x/java', 'nonsense'), isNull);
    });

    test('missing os.arch assumes 64-bit rather than 32-bit', () {
      final runtime = JavaProbe.parseExecutableOutput('/x/java', _jdk25Output)!;
      expect(runtime.arch, HostArch.x86_64);
      expect(runtime.is64Bit, isTrue);
      expect(runtime.majorVersion, 25);
    });
  });

  group('probe', () {
    test('parses a successful invocation', () async {
      final probe = JavaProbe(
        runProcess: (exe, args) async {
          expect(exe, '/x/bin/java');
          expect(args, contains('-XshowSettings:properties'));
          return const ProcessResultLike(
            exitCode: 0,
            stdout: '',
            stderr: _jdk17Output,
          );
        },
      );
      final runtime = await probe.probe('/x/bin/java');
      expect(runtime!.majorVersion, 17);
    });

    test('a missing executable yields null, not an exception', () async {
      final probe = JavaProbe(
        runProcess: (exe, args) async =>
            throw const ProcessException('java', [], 'No such file'),
      );
      expect(await probe.probe('/nope/java'), isNull);
    });

    test('a non-zero exit with no version yields null', () async {
      final probe = JavaProbe(
        runProcess: (exe, args) async =>
            const ProcessResultLike(exitCode: 1, stdout: '', stderr: 'boom'),
      );
      expect(await probe.probe('/x/java'), isNull);
    });
  });

  group('search roots', () {
    test('windows covers the usual install roots', () {
      final roots = javaSearchRoots(HostOs.windows);
      final dirs = roots.map((r) => r.directory).toList();
      expect(dirs, contains(r'C:\Program Files\Java'));
      expect(dirs, contains(r'C:\Program Files\Eclipse Adoptium'));
      expect(dirs, contains(r'C:\Program Files\Microsoft'));
      expect(dirs, contains(r'C:\Program Files\Zulu'));
      expect(
        roots.every((r) => r.relativeExecutable == r'bin\java.exe'),
        isTrue,
      );
    });

    test('macOS looks inside JavaVirtualMachines homes', () {
      final roots = javaSearchRoots(HostOs.osx);
      expect(roots.first.directory, '/Library/Java/JavaVirtualMachines');
      expect(roots.first.relativeExecutable, 'Contents/Home/bin/java');
    });

    test('linux looks in /usr/lib/jvm', () {
      final roots = javaSearchRoots(HostOs.linux);
      expect(roots.first.directory, '/usr/lib/jvm');
      expect(roots.first.relativeExecutable, 'bin/java');
    });

    test('other launchers\' runtimes are search roots, three levels deep', () {
      // The case behind "it launches in Prism but not here": Prism keeps its JVMs
      // in its own directory, so a user with no system JDK still has a Java 25 on
      // disk. Not looking there is a launcher bug, not a missing JVM.
      final roots = javaSearchRoots(HostOs.linux, home: '/home/u');
      final prism = roots.firstWhere(
        (r) => r.directory.endsWith('PrismLauncher/java'),
      );
      expect(prism.depth, 3);
      expect(prism.directory, '/home/u/.local/share/PrismLauncher/java');

      final os = javaSearchRoots(HostOs.osx, home: '/Users/u');
      expect(
        os.map((r) => r.directory),
        contains('/Users/u/Library/Application Support/PrismLauncher/java'),
      );
    });
  });

  group('search paths', () {
    test('windows JAVA_HOME gets a .exe suffix', () {
      final paths = defaultJavaSearchPaths(
        os: HostOs.windows,
        javaHome: r'C:\jdk17',
      );
      expect(paths.first, r'C:\jdk17\bin\java.exe');
    });

    test('JAVA_HOME comes before distro paths on linux', () {
      final paths = defaultJavaSearchPaths(
        os: HostOs.linux,
        javaHome: '/opt/jdk21',
      );
      expect(paths.first, '/opt/jdk21/bin/java');
    });

    test('a JRE nested in another launcher\'s directory is found', () {
      final tmp = Directory.systemTemp.createTempSync('java-home');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final java = File(
        '${tmp.path}/.local/share/PrismLauncher/java/temurin/25.0.1/bin/java',
      )..createSync(recursive: true);
      File('${tmp.path}/.minecraft/runtime/java-runtime-delta/bin/java')
          .createSync(recursive: true);
      File('${tmp.path}/.jdks/temurin-21/bin/java').createSync(recursive: true);

      final paths = defaultJavaSearchPaths(
        os: HostOs.linux,
        env: {'HOME': tmp.path},
      );

      expect(paths, contains(java.path));
      expect(
        paths,
        contains('${tmp.path}/.minecraft/runtime/java-runtime-delta/bin/java'),
      );
      expect(paths, contains('${tmp.path}/.jdks/temurin-21/bin/java'));
    });

    test('a user-supplied directory is scanned like an install root', () {
      final tmp = Directory.systemTemp.createTempSync('java-extra');
      addTearDown(() => tmp.deleteSync(recursive: true));
      // Both shapes a user might point at: the JDK home itself, and a folder of
      // JDKs (a toolchain manager's layout).
      final direct = File('${tmp.path}/jdk-25/bin/java')
        ..createSync(recursive: true);
      final nested = File('${tmp.path}/jdks/temurin-21/bin/java')
        ..createSync(recursive: true);

      final paths = defaultJavaSearchPaths(
        os: HostOs.linux,
        extraRoots: [tmp.path, '${tmp.path}/jdks'],
      );

      expect(paths, contains(direct.path));
      expect(paths, contains(nested.path));
    });

    test('managed roots are searched before JAVA_HOME', () {
      final paths = defaultJavaSearchPaths(
        os: HostOs.linux,
        javaHome: '/opt/jdk21',
        managedRoots: ['/launcher/java/25/bin/java'],
      );
      expect(paths.first, '/launcher/java/25/bin/java');
      expect(paths[1], '/opt/jdk21/bin/java');
    });
  });

  group('selectRuntime', () {
    JavaRuntime java(
      int major, {
      HostArch arch = HostArch.x86_64,
      JavaSource source = JavaSource.scanned,
    }) => JavaRuntime(
      path: '/jdk$major/bin/java',
      majorVersion: major,
      versionString: '$major.0.0',
      vendor: 'test',
      arch: arch,
      source: source,
    );

    test('picks the exact major when available', () {
      final chosen = selectRuntime([java(8), java(17), java(21)], 17);
      expect(chosen!.majorVersion, 17);
    });

    test('picks the lowest newer major when no exact match', () {
      final chosen = selectRuntime([java(8), java(21), java(25)], 17);
      expect(chosen!.majorVersion, 21);
    });

    test('never returns a runtime older than required', () {
      expect(selectRuntime([java(8), java(11)], 17), isNull);
    });

    test('unknown requirement returns null when nothing is installed', () {
      expect(selectRuntime([], 17), isNull);
    });

    test('prefers a managed runtime on a tie', () {
      final chosen = selectRuntime([
        java(17, source: JavaSource.scanned),
        java(17, source: JavaSource.managed),
      ], 17);
      expect(chosen!.source, JavaSource.managed);
    });

    test('a Java 8 runtime is correctly judged unfit for a modern version', () {
      expect(java(8).satisfies(17), isFalse);
      expect(java(21).satisfies(17), isTrue);
    });
  });

  group('JavaManager', () {
    test('scan deduplicates paths and keeps discovered runtimes', () async {
      var probes = 0;
      final manager = JavaManager(
        hostOs: HostOs.linux,
        probe: JavaProbe(
          runProcess: (exe, args) async {
            probes++;
            return ProcessResultLike(
              exitCode: 0,
              stdout: '',
              stderr: '    java.version = 1.8.0_402\n    os.arch = amd64\n',
            );
          },
        ),
      );

      await manager.scan(environment: {'JAVA_HOME': '/opt/jdk8'});
      expect(manager.hasScanned, isTrue);
      // The JAVA_HOME runtime is found; nothing else exists in CI.
      expect(manager.runtimes, isNotEmpty);
      expect(probes, greaterThanOrEqualTo(1));
      expect(manager.majors, contains(8));
    });

    test(
      'bestFor returns null before anything installed satisfies it',
      () async {
        final manager = JavaManager(
          hostOs: HostOs.linux,
          probe: JavaProbe(
            runProcess: (exe, args) async => const ProcessResultLike(
              exitCode: 0,
              stdout: '',
              stderr: '    java.version = 1.8.0_402\n',
            ),
          ),
        );
        await manager.scan(environment: {'JAVA_HOME': '/opt/jdk8'});
        expect(manager.bestFor(17), isNull);
        expect(manager.bestFor(8), isNotNull);
      },
    );

    test('add() replaces a runtime at the same path', () {
      final manager = JavaManager(hostOs: HostOs.linux);
      manager.add(
        const JavaRuntime(
          path: '/a/java',
          majorVersion: 17,
          versionString: '17',
          vendor: 'x',
          arch: HostArch.x86_64,
        ),
      );
      manager.add(
        const JavaRuntime(
          path: '/a/java',
          majorVersion: 21,
          versionString: '21',
          vendor: 'x',
          arch: HostArch.x86_64,
        ),
      );
      expect(manager.runtimes, hasLength(1));
      expect(manager.runtimes.single.majorVersion, 21);
    });

    test('round-trips through json for the settings cache', () {
      const runtime = JavaRuntime(
        path: '/jdk17/bin/java',
        majorVersion: 17,
        versionString: '17.0.9',
        vendor: 'Adoptium',
        arch: HostArch.arm64,
      );
      final restored = JavaRuntime.fromJson(runtime.toJson());
      expect(restored.path, runtime.path);
      expect(restored.majorVersion, 17);
      expect(restored.arch, HostArch.arm64);
    });
  });
}
