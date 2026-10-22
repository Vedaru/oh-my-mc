import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/mc/host.dart';
import 'package:oh_my_mc/core/mc/java_catalog.dart';
import 'package:oh_my_mc/core/mc/java_manager.dart';
import 'package:oh_my_mc/core/mc/java_provisioner.dart';
import 'package:oh_my_mc/core/net/progress.dart';
import 'package:oh_my_mc/data/java_providers.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/ui/motion/motion.dart';
import 'package:oh_my_mc/ui/setup/java_panel.dart';

import '../support/harness.dart';

import 'package:path/path.dart' as p;

/// Holds the panel at whichever install state a test needs, so no test opens a
/// socket. The real fetch/provision path is covered against a loopback server in
/// `test/data/java_providers_test.dart`.
class ScriptedJavaInstall extends JavaInstallController {
  final installed = <String>[];
  int cancelCalls = 0;

  @override
  JavaInstallState build() => const JavaInstallIdle();

  @override
  Future<void> install(JavaRuntimeChoice choice) async {
    installed.add(choice.component);
  }

  @override
  void cancel() {
    cancelCalls++;
    state = const JavaInstallCancelled();
  }

  /// Puts the controller into [next] so the panel can be tested in a state that
  /// only a real download would otherwise reach.
  void show(JavaInstallState next) => state = next;
}

JavaCatalog _catalog() => JavaCatalog.fromJson({
  'linux': {
    'java-runtime-gamma': [
      {
        'availability': {'group': 0, 'progress': 100},
        'manifest': {
          'url': 'https://example.invalid/gamma.json',
          'sha1': 'aa',
          'size': 100,
        },
        'version': {'name': '17.0.15', 'released': '2024-01-01'},
      },
    ],
  },
});

JavaRuntimeChoice _choice() => JavaRuntimeChoice(
  component: 'java-runtime-gamma',
  majorVersion: 17,
  build: _catalog().builds('linux', 'java-runtime-gamma').single,
);

void main() {
  late Directory data;

  setUp(() async {
    data = await Directory.systemTemp.createTemp('ommc-java-panel-');
  });

  tearDown(() async {
    if (await data.exists()) await data.delete(recursive: true);
  });

  Future<ScriptedJavaInstall> pump(
    WidgetTester tester,
    JavaRequirement requirement,
  ) async {
    final install = ScriptedJavaInstall();
    final container = ProviderContainer(
      overrides: [
        launcherPathsProvider.overrideWithValue(
          LauncherPaths(data: data, game: Directory(p.join(data.path, 'game'))),
        ),
        javaProvisionControllerProvider.overrideWith(() => install),
      ],
    );
    addTearDown(container.dispose);

    await pumpScreen(
      tester,
      container,
      JavaPanel(requirement: requirement),
      motion: Motion.none,
      settle: false,
    );
    return install;
  }

  testWidgets('a downloadable runtime shows a button that starts the install', (
    tester,
  ) async {
    final install = await pump(
      tester,
      JavaRequirementDownloadable(choice: _choice(), catalog: _catalog()),
    );

    expect(find.text('Java 17 is required'), findsOneWidget);
    expect(find.text('Download and install'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('java-download')));
    // The button's ink animation keeps a timer alive past the assertions; drain
    // it or the framework fails the test on a pending timer.
    await tester.pump(const Duration(milliseconds: 200));

    expect(install.installed, ['java-runtime-gamma']);
  });

  testWidgets('an installed runtime offers nothing to download', (
    tester,
  ) async {
    await pump(
      tester,
      JavaRequirementSatisfied(
        JavaRuntime(
          path: '/usr/lib/jvm/java-17/bin/java',
          majorVersion: 17,
          versionString: '17.0.15',
          vendor: 'Temurin',
          arch: HostArch.x86_64,
          source: JavaSource.scanned,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('java-download')), findsNothing);
    expect(find.textContaining('17'), findsOneWidget);
  });

  testWidgets('an unavailable runtime explains itself without a button', (
    tester,
  ) async {
    await pump(
      tester,
      const JavaRequirementUnavailable(
        JavaUnavailableReason.noBuildForPlatform,
        majorVersion: 8,
      ),
    );

    expect(find.byKey(const ValueKey('java-download')), findsNothing);
    expect(find.textContaining('No Java 8 build'), findsOneWidget);
  });

  testWidgets(
    'progress shows bytes and a bar, and cancel reaches the controller',
    (tester) async {
      final install = await pump(
        tester,
        JavaRequirementDownloadable(choice: _choice(), catalog: _catalog()),
      );
      // Drive the controller's own state instead of faking the panel: the panel
      // must render whatever the controller reports.
      install.show(
        const JavaInstallRunning(
          progress: JavaProvisionProgress(
            phase: JavaProvisionPhase.download,
            step: 2,
            steps: 3,
            download: DownloadProgress(
              filesDone: 3,
              filesTotal: 40,
              bytesDone: 4 * 1024 * 1024,
              bytesTotal: 40 * 1024 * 1024,
              bytesPerSecond: 1024 * 1024,
            ),
          ),
          bytesPerSecond: 1024 * 1024,
        ),
      );
      await tester.pump();

      expect(find.text('4.0 MB / 40.0 MB'), findsOneWidget);
      expect(find.byType(m3.LinearProgressIndicator), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('java-cancel')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(install.cancelCalls, 1);
    },
  );

  testWidgets('a finished install says so and can be dismissed', (
    tester,
  ) async {
    final install = await pump(
      tester,
      JavaRequirementDownloadable(choice: _choice(), catalog: _catalog()),
    );
    install.show(
      const JavaInstallDone(
        executable: '/data/runtimes/java-runtime-gamma-17.0.15/bin/java',
        majorVersion: 17,
        bytes: 100,
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('java-done')), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pump(const Duration(milliseconds: 200));

    // Back to the offer for the version that still is not installed.
    expect(find.byKey(const ValueKey('java-download')), findsOneWidget);
  });
}
