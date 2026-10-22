import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/mc/host.dart';
import 'package:oh_my_mc/core/mc/java_catalog.dart';
import 'package:oh_my_mc/core/mc/java_manager.dart';
import 'package:oh_my_mc/core/mc/java_provisioner.dart';
import 'package:oh_my_mc/data/java_providers.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:path/path.dart' as p;

/// What the launch screen decides when a version needs Java.
///
/// The rule this suite pins down: **never download what is already installed**.
/// A launcher that fetches 96 MB to replace a working JVM is the kind of thing
/// users notice, and the whole "found Java 17 on this computer" branch exists to
/// prevent it.
void main() {
  late Directory data;

  setUp(() async {
    data = await Directory.systemTemp.createTemp('java_providers_test');
  });

  tearDown(() async {
    if (await data.exists()) await data.delete(recursive: true);
  });

  JavaRuntime runtime(int major, {JavaSource source = JavaSource.scanned}) =>
      JavaRuntime(
        path: '/usr/lib/jvm/java-$major/bin/java',
        majorVersion: major,
        versionString: '$major.0.1',
        vendor: 'Test',
        arch: HostArch.x86_64,
        source: source,
      );

  /// One platform, one build per component name. The catalog is
  /// `platform -> component -> [build]`, which is why a component with no build
  /// for a platform is an empty list rather than a missing key.
  JavaCatalog catalogWith({
    required String platform,
    required List<String> components,
    String version = '17.0.15',
  }) => JavaCatalog.fromJson({
    platform: {
      for (final component in components)
        component: [
          {
            'availability': {'group': 0, 'progress': 100},
            'manifest': {
              'url': 'https://example.invalid/$component.json',
              'sha1': 'aa',
              'size': 10,
            },
            'version': {'name': version, 'released': '2024-01-01'},
          },
        ],
    },
  });

  group('resolveJavaRequirement', () {
    test('an installed exact match is used and nothing is downloaded', () {
      final requirement = resolveJavaRequirement(
        requiredMajor: 17,
        installed: [runtime(17)],
        catalog: catalogWith(
          platform: 'linux',
          components: ['java-runtime-gamma'],
        ),
        hostOs: HostOs.linux,
        hostArch: HostArch.x86_64,
      );

      expect(requirement, isA<JavaRequirementSatisfied>());
      expect(
        (requirement as JavaRequirementSatisfied).runtime.majorVersion,
        17,
      );
    });

    test('a newer installed runtime satisfies an older requirement', () {
      // Java 21 runs a version that declared 17; offering a download would be
      // asking the user to spend 96 MB to downgrade.
      final requirement = resolveJavaRequirement(
        requiredMajor: 17,
        installed: [runtime(21)],
        catalog: catalogWith(
          platform: 'linux',
          components: ['java-runtime-gamma'],
        ),
        hostOs: HostOs.linux,
        hostArch: HostArch.x86_64,
      );
      expect(requirement, isA<JavaRequirementSatisfied>());
    });

    test('with nothing installed, the catalog is offered instead', () {
      final requirement = resolveJavaRequirement(
        requiredMajor: 17,
        installed: const [],
        catalog: catalogWith(
          platform: 'linux',
          components: ['java-runtime-gamma'],
        ),
        hostOs: HostOs.linux,
        hostArch: HostArch.x86_64,
      );

      expect(requirement, isA<JavaRequirementDownloadable>());
      expect((requirement as JavaRequirementDownloadable).majorVersion, 17);
    });

    test('no catalog and no JVM is unavailable, not a silent download', () {
      final requirement = resolveJavaRequirement(
        requiredMajor: 17,
        installed: const [],
        catalog: null,
        hostOs: HostOs.linux,
        hostArch: HostArch.x86_64,
      );
      expect(requirement, isA<JavaRequirementUnavailable>());
      expect(
        (requirement as JavaRequirementUnavailable).reason,
        JavaUnavailableReason.catalogUnavailable,
      );
    });

    test('a version too old for any published build is unavailable', () {
      // Java 8 on Apple Silicon: the catalog has no arm64 jre-legacy, and an
      // x86_64 JRE that cannot start is worse than saying so.
      final requirement = resolveJavaRequirement(
        requiredMajor: 8,
        declaredComponent: 'jre-legacy',
        installed: const [],
        catalog: catalogWith(
          platform: 'mac-os-arm64',
          components: ['java-runtime-gamma'],
        ),
        hostOs: HostOs.osx,
        hostArch: HostArch.arm64,
      );
      expect(
        (requirement as JavaRequirementUnavailable).reason,
        JavaUnavailableReason.noBuildForPlatform,
        reason:
            'the message must name the platform, so the code has to be '
            'distinguishable from a network failure',
      );
    });
  });

  group('ManagedJavaRuntime', () {
    Directory install(String name) {
      final root = Directory(p.join(data.path, 'runtimes', name))
        ..createSync(recursive: true);
      File(p.join(root.path, 'bin', 'java'))
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\n');
      return root;
    }

    test('reads the component and version back out of the directory name', () {
      final runtime = ManagedJavaRuntime(
        executable: '/x/bin/java',
        directory: Directory('/x'),
        component: 'java-runtime-gamma',
        versionName: '17.0.15',
      );
      expect(runtime.component, 'java-runtime-gamma');
      expect(runtime.versionName, '17.0.15');
      expect(runtime.majorVersion?.majorVersion, 17);
    });

    test('an unrecognised component has no major version, rather than a guess', () {
      final runtime = ManagedJavaRuntime(
        executable: '/x/bin/java',
        directory: Directory('/x'),
        component: 'something-new',
        versionName: '1.2.3',
      );
      // Guessing 1 here would make an unknown runtime look like a valid Java 1.
      expect(runtime.majorVersion, isNull);
    });

    test('disk usage counts the whole tree, not just the executable', () {
      final root = install('java-runtime-gamma-17.0.15');
      File(p.join(root.path, 'lib', 'modules'))
        ..createSync(recursive: true)
        ..writeAsStringSync('x' * 500);

      final runtime = ManagedJavaRuntime(
        executable: p.join(root.path, 'bin', 'java'),
        directory: root,
        component: 'java-runtime-gamma',
        versionName: '17.0.15',
      );
      expect(runtime.diskBytes, greaterThan(500));
    });
  });

  group('JavaRuntimesController', () {
    test('lists real runtimes and ignores a staging tree', () async {
      final paths = _pathsFor(data);
      for (final name in [
        'java-runtime-gamma-17.0.15',
        'jre-legacy-8u202',
        'java-runtime-delta-21.0.7.staging',
      ]) {
        final root = Directory(p.join(data.path, 'runtimes', name));
        File(p.join(root.path, 'bin', 'java'))
          ..createSync(recursive: true)
          ..writeAsStringSync('#!/bin/sh\n');
      }

      final container = ProviderContainer(
        overrides: [launcherPathsProvider.overrideWithValue(paths)],
      );
      addTearDown(container.dispose);

      final runtimes = await container.read(javaRuntimesProvider.future);
      expect(runtimes, hasLength(2));
      expect(
        runtimes.map((r) => r.component),
        containsAll(['java-runtime-gamma', 'jre-legacy']),
      );
    });

    test('a directory with no java is not listed', () async {
      Directory(p.join(data.path, 'runtimes', 'java-runtime-gamma-17.0.15'))
          .createSync(recursive: true);

      final container = ProviderContainer(
        overrides: [launcherPathsProvider.overrideWithValue(_pathsFor(data))],
      );
      addTearDown(container.dispose);

      expect(await container.read(javaRuntimesProvider.future), isEmpty);
    });

    test('remove deletes the tree and the list refreshes', () async {
      final root = Directory(
        p.join(data.path, 'runtimes', 'java-runtime-gamma-17.0.15'),
      );
      File(p.join(root.path, 'bin', 'java'))
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\n');

      final container = ProviderContainer(
        overrides: [launcherPathsProvider.overrideWithValue(_pathsFor(data))],
      );
      addTearDown(container.dispose);

      final runtimes = await container.read(javaRuntimesProvider.future);
      expect(runtimes, hasLength(1));

      final removed = await container
          .read(javaRuntimesProvider.notifier)
          .remove(runtimes.single);
      expect(removed, isTrue);
      expect(root.existsSync(), isFalse);
      expect(await container.read(javaRuntimesProvider.future), isEmpty);
    });

    test(
      'a runtime written by the provisioner is found by the launch path',
      () async {
        // The seam that matters: `JavaProvisioner` writes
        // `<data>/runtimes/<component>-<version>/bin/java`, and
        // `managedJavaExecutables` must hand exactly that path to `scan`.
        final root = Directory(
          p.join(data.path, 'runtimes', 'java-runtime-gamma-17.0.15'),
        );
        final executable = File(p.join(root.path, 'bin', 'java'))
          ..createSync(recursive: true)
          ..writeAsStringSync('#!/bin/sh\n');

        expect(managedJavaExecutables(data), [executable.path]);

        final manager = JavaManager(
          hostOs: HostOs.linux,
          probe: JavaProbe(
            runProcess: (exe, args) async => ProcessResultLike(
              exitCode: 0,
              stdout: '',
              stderr: '    java.version = 17.0.15\n    os.arch = amd64\n',
            ),
          ),
        );
        final found = await manager.scan(
          environment: const {},
          managedRoots: managedJavaExecutables(data),
        );
        // The test machine may have its own JDK, so this asserts on the entry
        // that came from `managedRoots` rather than on the count.
        final ours = found.singleWhere((r) => r.path == executable.path);
        expect(
          ours.source,
          JavaSource.managed,
          reason: 'a downloaded runtime must be deletable as ours',
        );
        expect(manager.bestFor(17)?.path, isNotNull);
      },
    );
  });
}

/// A [LauncherPaths] whose data directory is [data] and whose game tree is a
/// sibling, which is the production relationship.
LauncherPaths _pathsFor(Directory data) =>
    LauncherPaths(data: data, game: Directory(p.join(data.path, 'game')));
