import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/core/install/version_installer.dart';
import 'package:oh_my_mc/core/net/progress.dart';
import 'package:oh_my_mc/core/net/version_manifest.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/data/install_providers.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/ui/components/skeleton_block.dart';
import 'package:oh_my_mc/ui/download/download_screen.dart';
import 'package:oh_my_mc/ui/motion/motion.dart';
import 'package:oh_my_mc/ui/theme/app_theme.dart';

import '../support/harness.dart';

/// The property every new animated surface in this milestone owes: with motion
/// off it renders its end state and schedules **no frames**.
///
/// `transientCallbackCount` is the assertion, not a proxy: a ticker that is
/// merely set to a zero duration still registers a transient callback for a
/// frame, and that is exactly what "motion off is free" has to rule out.
void _expectNoTicker(WidgetTester tester) =>
    expect(tester.binding.transientCallbackCount, 0);

Widget _app(Motion motion, Widget child) => m3.MaterialApp(
  theme: AppTheme.material(Brightness.light),
  home: MotionScope(
    motion: motion,
    child: m3.Scaffold(body: m3.Center(child: child)),
  ),
);

/// A version list that is ready immediately: the download screen is only the
/// backdrop for the progress assertions here.
class _ReadyVersions extends VersionListController {
  @override
  VersionListState build() => VersionListReady(
    VersionManifest.fromJson({
      'latest': {'release': '1.20.1', 'snapshot': '1.20.1'},
      'versions': [
        {
          'id': '1.20.1',
          'type': 'release',
          'url': 'https://example.invalid/1.20.1.json',
          'sha1': 'aa',
          'releaseTime': '2023-06-12T00:00:00+00:00',
        },
      ],
    }),
  );
}

class _NoInstalled extends InstalledVersions {
  @override
  Set<String> build() => const {};
}

/// Holds a running install whose *bytes* are already complete.
///
/// This is the case the clamp exists for: the download is done but the pipeline
/// is still unpacking natives, so the panel is still "running" and must not say
/// 100%.
class _CompleteBytesRunning extends InstallController {
  @override
  InstallState build() => const InstallIdle();

  void start() => state = const InstallRunning(
    versionId: '1.20.1',
    progress: InstallProgress(
      phase: InstallPhase.natives,
      step: 7,
      steps: 9,
      download: DownloadProgress(
        filesDone: 100,
        filesTotal: 100,
        bytesDone: 20 * 1024 * 1024,
        bytesTotal: 20 * 1024 * 1024,
      ),
    ),
  );

  @override
  void cancel() => state = const InstallCancelled(versionId: '1.20.1');

  @override
  void reset() => state = const InstallIdle();

  @override
  Future<void> install(
    String versionId, {
    bool includeAssets = true,
    LoaderKind? loader,
    String? loaderVersion,
  }) async {}
}

void main() {
  group('Emphasis', () {
    testWidgets('motion off renders the child and allocates no ticker', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Motion.none,
          const Emphasis(
            child: m3.SizedBox(
              key: m3.ValueKey('target'),
              width: 80,
              height: 40,
            ),
          ),
        ),
      );

      // No scale wrapper at all: the disabled tree is the tree the caller wrote.
      expect(find.byType(AnimatedScale), findsNothing);
      expect(find.byKey(const m3.ValueKey('target')), findsOneWidget);
      _expectNoTicker(tester);
    });

    testWidgets('motion on shrinks while the pointer is down and returns', (
      tester,
    ) async {
      // The child has to be hit-testable, exactly like the button `Emphasis`
      // wraps in the app: `Listener` defaults to `deferToChild`, so a bare
      // `SizedBox` has no press surface to hear in the first place.
      await tester.pumpWidget(
        _app(
          Motion.full,
          const Emphasis(
            child: m3.ColoredBox(
              key: m3.ValueKey('target'),
              color: m3.Color(0xFF202020),
              child: m3.SizedBox(width: 80, height: 40),
            ),
          ),
        ),
      );

      final target = find.byKey(const m3.ValueKey('target'));
      final gesture = await tester.startGesture(tester.getCenter(target));
      await tester.pump();

      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        lessThan(1),
      );

      await gesture.up();
      await tester.pumpAndSettle();

      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    });
  });

  group('AnimatedCount', () {
    testWidgets('motion off shows the final value with no ticker', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Motion.none,
          AnimatedCount(value: 4096, builder: (_, v) => m3.Text('v$v')),
        ),
      );

      expect(find.text('v4096'), findsOneWidget);
      _expectNoTicker(tester);
    });

    testWidgets('motion on counts to the new value instead of snapping', (
      tester,
    ) async {
      var value = 0;
      late StateSetter setValue;

      await tester.pumpWidget(
        _app(
          Motion.full,
          StatefulBuilder(
            builder: (context, setState) {
              setValue = setState;
              return AnimatedCount(
                value: value,
                builder: (_, v) => m3.Text('v$v'),
              );
            },
          ),
        ),
      );
      expect(find.text('v0'), findsOneWidget);

      setValue(() => value = 100);
      await tester.pump();

      // The first frame after the change still shows the old number: the digits
      // travel rather than swap.
      expect(find.text('v100'), findsNothing);

      await tester.pumpAndSettle();
      expect(find.text('v100'), findsOneWidget);
    });
  });

  group('Skeleton', () {
    testWidgets('draws its bones with motion off, and stays still', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Motion.none,
          const Skeleton(
            child: m3.Column(
              mainAxisSize: m3.MainAxisSize.min,
              children: [
                SkeletonBlock(width: 120, height: 12),
                m3.SizedBox(height: 8),
                SkeletonBlock(width: 80, height: 12),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(SkeletonBlock), findsNWidgets(2));
      _expectNoTicker(tester);

      // Half a second of frames must not wake it: a still skeleton is the point.
      await tester.pump(const Duration(milliseconds: 500));
      _expectNoTicker(tester);
    });
  });

  group('install progress', () {
    testWidgets('a running install never reports completion', (tester) async {
      final installs = _CompleteBytesRunning();
      final container = ProviderContainer(
        overrides: [
          versionListProvider.overrideWith(_ReadyVersions.new),
          installControllerProvider.overrideWith(() => installs),
          installedVersionsProvider.overrideWith(_NoInstalled.new),
          // The panel renders the install log, and the log lives under `<data>`.
          launcherPathsProvider.overrideWith((ref) {
            final data = Directory.systemTemp.createTempSync('motion-install');
            ref.onDispose(() => data.deleteSync(recursive: true));
            return LauncherPaths(
              data: data,
              game: Directory('${data.path}/game'),
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      await pumpScreen(
        tester,
        container,
        const DownloadScreen(),
        motion: Motion.none,
        settle: false,
      );

      installs.start();
      await tester.pump();
      await tester.pump(Durations.fast);

      final bars = tester
          .widgetList<m3.LinearProgressIndicator>(
            find.byType(m3.LinearProgressIndicator),
          )
          .toList();
      expect(bars, hasLength(1));
      expect(bars.single.value, isNotNull);
      expect(
        bars.single.value!,
        lessThan(1.0),
        reason: 'a running install must stay short of the end',
      );

      // The digits agree with the bar rather than with the raw fraction.
      expect(find.text('100%'), findsNothing);
      expect(find.byKey(const m3.ValueKey('download-percent')), findsOneWidget);
    });
  });
}
