import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/net/progress.dart';
import 'package:oh_my_mc/core/install/version_installer.dart';
import 'package:oh_my_mc/data/install_providers.dart';
import 'package:oh_my_mc/data/launch_factory.dart';

import '../support/mini_world.dart';

void main() {
  late MiniWorld world;
  late Directory tmp;
  late LauncherPaths paths;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ommc-install-');
    paths = LauncherPaths(
      data: Directory('${tmp.path}/data')..createSync(recursive: true),
      game: Directory('${tmp.path}/game')..createSync(recursive: true),
    );
    world = await MiniWorld.start();
  });

  tearDown(() async {
    await world.close();
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  ProviderContainer container({bool failEverything = false}) {
    world.failEverything = failEverything;
    final container = ProviderContainer(
      overrides: [
        launcherPathsProvider.overrideWith((ref) => paths),
        installerFactoryProvider.overrideWith(
          (ref) =>
              () => world.installer(
                File('${paths.game.path}/manifest-cache.json'),
              ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('InstallRunning.fraction', () {
    const idle = InstallProgress(
      phase: InstallPhase.manifest,
      step: 1,
      steps: 9,
    );

    test('a byte counter wins over the step count', () {
      const running = InstallRunning(
        versionId: 'x',
        progress: InstallProgress(
          phase: InstallPhase.download,
          step: 6,
          steps: 9,
          download: DownloadProgress(
            filesDone: 1,
            filesTotal: 4,
            bytesDone: 250,
            bytesTotal: 1000,
          ),
        ),
      );
      expect(running.fraction, 0.25);
    });

    test('a phase without bytes still moves forward', () {
      // The alternative - a determinate bar stuck at 0% through a one-minute
      // natives unpack - is indistinguishable from a hang.
      const first = InstallRunning(versionId: 'x', progress: idle);
      const later = InstallRunning(
        versionId: 'x',
        progress: InstallProgress(
          phase: InstallPhase.verify,
          step: 9,
          steps: 9,
        ),
      );
      expect(first.fraction, 0);
      expect(later.fraction, closeTo(8 / 9, 1e-9));
      expect(later.fraction, greaterThan(first.fraction));
    });

    test('an unknown step count does not divide by zero', () {
      const running = InstallRunning(
        versionId: 'x',
        progress: InstallProgress(phase: InstallPhase.planning),
      );
      expect(running.fraction, 0);
    });
  });

  group('install controller', () {
    test(
      'a successful install reaches InstallDone and flips the row',
      () async {
        await world.publishVersion('1.20.1');
        final c = container();
        final notifier = c.read(installControllerProvider.notifier);

        // Reading first also proves the installed set can be read before any
        // install happened, which is the state on a fresh profile.
        c.read(installedVersionsProvider);
        await pumpEventQueue();
        expect(c.read(installedVersionsProvider), isEmpty);

        await notifier.install('1.20.1', includeAssets: false);

        final state = c.read(installControllerProvider);
        expect(state, isA<InstallDone>());
        final done = state as InstallDone;
        expect(done.versionId, '1.20.1');
        expect(
          done.isClean,
          isTrue,
          reason: 'the plan was satisfied, so nothing should need repair',
        );
        expect(done.fileCount, greaterThan(0));

        await pumpEventQueue();
        expect(
          c.read(installedVersionsProvider),
          {'1.20.1'},
          reason:
              'the version list marks rows from disk; without a refresh the '
              'row the user just installed still offers Install',
        );
      },
    );

    test('progress is reported while the install runs', () async {
      await world.publishVersion('1.20.1');
      final c = container();
      final seen = <InstallPhase>{};

      c.listen(installControllerProvider, (_, next) {
        if (next is InstallRunning) seen.add(next.progress.phase);
      });

      await c
          .read(installControllerProvider.notifier)
          .install('1.20.1', includeAssets: false);

      expect(seen, contains(InstallPhase.manifest));
      expect(
        seen,
        contains(InstallPhase.verify),
        reason: 'every phase must reach the UI, not just the download',
      );
    });

    test(
      'a network failure is reported with the cause, not swallowed',
      () async {
        // The manifest is absent, so the very first phase fails.
        final c = container(failEverything: true);
        await c.read(installControllerProvider.notifier).install('1.20.1');

        final state = c.read(installControllerProvider);
        expect(state, isA<InstallFailed>());
        expect((state as InstallFailed).versionId, '1.20.1');
        expect(
          state.message,
          isNotEmpty,
          reason: 'a bare "download failed" hides the actual cause',
        );
      },
    );

    test(
      'cancelling settles as cancelled and keeps the partial tree',
      () async {
        await world.publishVersion('1.20.1');
        final c = container();
        final notifier = c.read(installControllerProvider.notifier);

        // Hold every response open so the cancel lands mid-transfer rather than
        // after the install already finished.
        final gate = Completer<void>();
        world.stall = gate.future;

        final future = notifier.install('1.20.1', includeAssets: false);
        await pumpEventQueue();
        expect(c.read(installControllerProvider), isA<InstallRunning>());

        notifier.cancel();
        gate.complete();
        await future;

        expect(c.read(installControllerProvider), isA<InstallCancelled>());
        // Resume-not-restart is the whole reason a cancel keeps its bytes.
        expect(
          Directory(paths.gamePaths.root).existsSync(),
          isTrue,
          reason: 'the install root must survive a cancel',
        );
      },
    );

    test('a second install is ignored while one is running', () async {
      await world.publishVersion('1.20.1');
      final c = container();
      final notifier = c.read(installControllerProvider.notifier);
      final gate = Completer<void>();
      world.stall = gate.future;

      final first = notifier.install('1.20.1', includeAssets: false);
      await pumpEventQueue();
      // A second click would otherwise run two installers over the same
      // `libraries/` tree and hash-check each other's half-written files.
      await notifier.install('1.20.1', includeAssets: false);
      expect(c.read(installControllerProvider), isA<InstallRunning>());

      gate.complete();
      await first;
    });

    test('reset clears a finished result but not a running one', () async {
      await world.publishVersion('1.20.1');
      final c = container();
      final notifier = c.read(installControllerProvider.notifier);

      await notifier.install('1.20.1', includeAssets: false);
      expect(c.read(installControllerProvider), isA<InstallDone>());
      notifier.reset();
      expect(c.read(installControllerProvider), isA<InstallIdle>());
    });
  });

  group('installed version detection', () {
    test('a version without its JSON is not offered as installed', () async {
      // A half-deleted install cannot launch; marking it installed would make
      // the play button fail with no explanation.
      final dir = Directory(paths.gamePaths.versionDir('1.19.4'))
        ..createSync(recursive: true);
      await File('${dir.path}/1.19.4.jar').writeAsString('jar');

      final c = container();
      c.read(installedVersionsProvider);
      await pumpEventQueue();

      expect(c.read(installedVersionsProvider), isEmpty);
    });

    test('a complete version directory is reported', () async {
      final dir = Directory(paths.gamePaths.versionDir('1.19.4'))
        ..createSync(recursive: true);
      await File('${dir.path}/1.19.4.json').writeAsString('{}');

      final c = container();
      c.read(installedVersionsProvider);
      await pumpEventQueue();

      expect(c.read(installedVersionsProvider), {'1.19.4'});
    });

    test('a missing versions directory is empty, not an error', () async {
      final c = container();
      c.read(installedVersionsProvider);
      await pumpEventQueue();

      expect(c.read(installedVersionsProvider), isEmpty);
    });
  });
}
