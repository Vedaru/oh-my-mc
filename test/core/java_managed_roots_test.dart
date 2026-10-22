import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/mc/host.dart';
import 'package:oh_my_mc/core/mc/java_manager.dart';
import 'package:oh_my_mc/core/mc/java_provisioner.dart';
import 'package:path/path.dart' as p;

/// A provisioned runtime is only useful if the launch path can *find* it.
///
/// These tests cover the seam between `JavaProvisioner` (which writes
/// `<data>/runtimes/<component>-<version>/`) and `JavaManager.scan` (which reads
/// search roots). Neither side was wrong on its own; the join was simply never
/// made, so a downloaded JRE would have been invisible and the user would be
/// told to install Java they had just installed.
void main() {
  late Directory data;

  setUp(() async {
    data = await Directory.systemTemp.createTemp('java_roots_test');
  });

  tearDown(() async {
    if (await data.exists()) await data.delete(recursive: true);
  });

  /// Creates a plausible runtime tree and returns its root.
  Directory installRuntime(String name, {bool executable = true}) {
    final root = Directory(p.join(data.path, 'runtimes', name))
      ..createSync(recursive: true);
    Directory(p.join(root.path, 'bin')).createSync(recursive: true);
    File(p.join(root.path, 'bin', 'java'))
      ..createSync(recursive: true)
      ..writeAsStringSync('#!/bin/sh\n');
    if (executable) {
      Process.runSync('chmod', ['+x', p.join(root.path, 'bin', 'java')]);
    }
    return root;
  }

  group('managedJavaExecutables', () {
    test('is empty when nothing has been downloaded', () {
      expect(managedJavaExecutables(data), isEmpty);
    });

    test('finds the macOS bundle layout too', () {
      // Mojang's Darwin manifests root the tree at jre.bundle/Contents/Home,
      // so `<root>/bin/java` does not exist there.
      final root = Directory(
        p.join(data.path, 'runtimes', 'java-runtime-gamma-17.0.15'),
      )..createSync(recursive: true);
      final executable = File(
        p.join(root.path, 'jre.bundle', 'Contents', 'Home', 'bin', 'java'),
      );
      executable.parent.createSync(recursive: true);
      executable.writeAsStringSync('#!/bin/sh\n');
      expect(managedJavaExecutables(data), [executable.path]);
    });

    test('a runtime with no java at all is not offered', () {
      // Half-extracted without the .staging suffix: a crash, not a cancel.
      Directory(p.join(data.path, 'runtimes', 'java-runtime-gamma-17.0.15'))
          .createSync(recursive: true);
      expect(managedJavaExecutables(data), isEmpty);
    });

    test('lists each installed runtime', () {
      installRuntime('java-runtime-gamma-17.0.15');
      installRuntime('jre-legacy-8u202');
      expect(managedJavaExecutables(data), [
        p.join(
          data.path,
          'runtimes',
          'java-runtime-gamma-17.0.15',
          'bin',
          'java',
        ),
        p.join(data.path, 'runtimes', 'jre-legacy-8u202', 'bin', 'java'),
      ]);
    });

    test('skips a half-extracted staging tree', () {
      installRuntime('java-runtime-gamma-17.0.15');
      // A cancel leaves exactly this shape; probing it would find a `bin/java`
      // that cannot start, and report a phantom "Java 17 installed".
      installRuntime('java-runtime-delta-21.0.7.staging');
      expect(managedJavaExecutables(data), [
        p.join(
          data.path,
          'runtimes',
          'java-runtime-gamma-17.0.15',
          'bin',
          'java',
        ),
      ]);
    });

    test('ignores stray files next to the runtimes', () {
      installRuntime('java-runtime-gamma-17.0.15');
      File(p.join(data.path, 'runtimes', '.DS_Store')).writeAsStringSync('');
      expect(managedJavaExecutables(data), hasLength(1));
    });
  });

  group('JavaManager finds a managed runtime', () {
    test('scan over managedRoots reports it as source: managed', () async {
      final root = installRuntime('java-runtime-gamma-17.0.15');
      final probed = <String>[];
      final manager = JavaManager(
        hostOs: HostOs.linux,
        probe: JavaProbe(
          runProcess: (exe, args) async {
            probed.add(exe);
            return ProcessResultLike(
              exitCode: 0,
              stdout: '',
              stderr: '    java.version = 17.0.15\n    os.arch = aarch64\n',
            );
          },
        ),
      );

      final runtimes = await manager.scan(
        environment: const {},
        managedRoots: managedJavaExecutables(data),
      );

      expect(probed, contains(p.join(root.path, 'bin', 'java')));
      final managed = runtimes.where((r) => r.source == JavaSource.managed);
      expect(managed, hasLength(1));
      expect(managed.single.majorVersion, 17);
    });

    test('a managed runtime wins a tie against a scanned one', () async {
      // Same major on both: `selectRuntime` prefers the managed one because the
      // launcher knows exactly what it is and can replace it.
      installRuntime('java-runtime-gamma-17.0.15');
      final manager = JavaManager(
        hostOs: HostOs.linux,
        known: const [
          JavaRuntime(
            path: '/usr/lib/jvm/java-17/bin/java',
            majorVersion: 17,
            versionString: '17.0.9',
            vendor: 'Temurin',
            arch: HostArch.x86_64,
            source: JavaSource.scanned,
          ),
        ],
        probe: JavaProbe(
          runProcess: (exe, args) async => ProcessResultLike(
            exitCode: 0,
            stdout: '',
            stderr: '    java.version = 17.0.15\n    os.arch = aarch64\n',
          ),
        ),
      );

      await manager.scan(
        environment: const {},
        managedRoots: managedJavaExecutables(data),
      );

      final chosen = manager.bestFor(17);
      expect(chosen, isNotNull);
      expect(chosen!.source, JavaSource.managed);
    });

    test(
      'a staging tree is never probed, so it cannot fake an install',
      () async {
        installRuntime('java-runtime-gamma-17.0.15.staging');
        final probed = <String>[];
        final manager = JavaManager(
          hostOs: HostOs.linux,
          probe: JavaProbe(
            runProcess: (exe, args) async {
              probed.add(exe);
              return ProcessResultLike(
                exitCode: 0,
                stdout: '',
                stderr: '    java.version = 17.0.15\n',
              );
            },
          ),
        );

        await manager.scan(
          environment: const {},
          managedRoots: managedJavaExecutables(data),
        );

        expect(
          probed.where((path) => path.startsWith(data.path)),
          isEmpty,
          reason:
              'only the .staging tree exists, so none of our paths is probed',
        );
        expect(
          manager.runtimes.where((r) => r.path.startsWith(data.path)),
          isEmpty,
        );
      },
    );
  });
}
