import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/install/version_installer.dart';
import 'package:oh_my_mc/core/net/progress.dart';
import 'package:oh_my_mc/core/net/version_manifest.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/data/install_providers.dart';
import 'package:oh_my_mc/ui/download/download_screen.dart';
import 'package:oh_my_mc/ui/motion/motion.dart';

import '../support/harness.dart';

/// A manifest with one release, one snapshot and one ancient beta.
///
/// Built as a real [VersionManifest] rather than a stub so the screen's own
/// filtering runs against the same type production parses.
VersionManifest _manifest() => VersionManifest.fromJson({
  'latest': {'release': '1.20.1', 'snapshot': '24w14a'},
  'versions': [
    {
      'id': '1.20.1',
      'type': 'release',
      'url': 'https://example.invalid/1.20.1.json',
      'sha1': 'aa',
      'releaseTime': '2023-06-12T00:00:00+00:00',
    },
    {
      'id': '24w14a',
      'type': 'snapshot',
      'url': 'https://example.invalid/24w14a.json',
      'sha1': 'bb',
      'releaseTime': '2024-04-03T00:00:00+00:00',
    },
    {
      'id': 'b1.7.3',
      'type': 'old_beta',
      'url': 'https://example.invalid/b1.7.3.json',
      'sha1': 'cc',
      'releaseTime': '2011-07-08T00:00:00+00:00',
    },
  ],
});

/// Drives the install state by hand, so a widget test can hold the UI at each
/// state instead of racing a real install.
///
/// Only the *state* is faked. The pipeline is covered end to end against a
/// loopback server in `test/data/install_providers_test.dart`; what is under
/// test here is what the screen renders for each state.
class ScriptedInstallController extends InstallController {
  final installedCalled = <String>[];

  /// Which loader each call asked for; `LoaderKind.vanilla` when none was given.
  final loaders = <LoaderKind>[];
  int cancelCalls = 0;

  /// When set, [install] stops at [InstallRunning] and never finishes, which is
  /// what keeps the progress panel on screen for assertions.
  bool stall = false;

  @override
  InstallState build() => const InstallIdle();

  @override
  Future<void> install(
    String versionId, {
    bool includeAssets = true,
    LoaderKind? loader,
    String? loaderVersion,
  }) async {
    installedCalled.add(versionId);
    loaders.add(loader ?? LoaderKind.vanilla);
    state = InstallRunning(
      versionId: versionId,
      progress: const InstallProgress(
        phase: InstallPhase.download,
        step: 6,
        steps: 9,
        download: DownloadProgress(
          filesDone: 40,
          filesTotal: 100,
          bytesDone: 5 * 1024 * 1024,
          bytesTotal: 20 * 1024 * 1024,
          bytesPerSecond: 1024 * 1024,
          currentFile: 'libraries/com/example/lib.jar',
        ),
      ),
      bytesPerSecond: 1024 * 1024,
    );
    if (stall) return;
    state = InstallDone(versionId: versionId, problemCount: 0, fileCount: 100);
  }

  @override
  void cancel() {
    cancelCalls++;
    state = InstallCancelled(versionId: (state as InstallRunning).versionId);
  }

  @override
  void reset() => state = const InstallIdle();

  /// Jumps straight to the "installed, but files need repair" outcome.
  void finishWithProblems(String versionId, int problems) {
    state = InstallDone(
      versionId: versionId,
      problemCount: problems,
      fileCount: 100,
    );
  }

  /// Shows a failure the way the controller reports one.
  void fail(String versionId, String message) {
    state = InstallFailed(versionId: versionId, message: message);
  }
}

class ScriptedVersionList extends VersionListController {
  ScriptedVersionList(this.state0);

  final VersionListState state0;

  @override
  VersionListState build() => state0;
}

class ScriptedInstalled extends InstalledVersions {
  ScriptedInstalled(this.state0);

  final Set<String> state0;

  @override
  Set<String> build() => state0;
}

void main() {
  late Directory tmp;
  late ScriptedInstallController installs;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ommc-download-ui-');
    installs = ScriptedInstallController();
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    VersionListState? list,
    Set<String> installed = const {},
  }) async {
    final container = ProviderContainer(
      overrides: [
        versionListProvider.overrideWith(
          () => ScriptedVersionList(list ?? VersionListReady(_manifest())),
        ),
        installControllerProvider.overrideWith(() => installs),
        installedVersionsProvider.overrideWith(
          () => ScriptedInstalled(installed),
        ),
      ],
    );
    addTearDown(container.dispose);

    // A fixed pump, not `pumpAndSettle`: the staggered entrance is running and
    // an indeterminate progress bar never stops.
    await pumpScreen(
      tester,
      container,
      const DownloadScreen(),
      motion: Motion.none,
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  testWidgets('releases are listed; snapshots and old betas are hidden', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('1.20.1'), findsOneWidget);
    // A snapshot needs the toggle; an old beta cannot be installed at all, so
    // it is never offered.
    expect(find.text('24w14a'), findsNothing);
    expect(find.text('b1.7.3'), findsNothing);
  });

  testWidgets('the snapshot toggle reveals snapshots but still not old betas', (
    tester,
  ) async {
    await pump(tester);

    // The label is a sibling of the switch, not part of it, so tapping the text
    // would not toggle anything.
    await tester.tap(find.byType(m3.Switch));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('24w14a'), findsOneWidget);
    expect(find.text('b1.7.3'), findsNothing);
  });

  testWidgets('search filters the visible rows', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(m3.TextField), '1.20');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('1.20.1'), findsOneWidget);
  });

  testWidgets('an unmatched search names the query instead of going blank', (
    tester,
  ) async {
    await pump(tester);

    await tester.enterText(find.byType(m3.TextField), '9.99');
    await tester.pump(const Duration(milliseconds: 400));

    // The search field holds the query too, so the assertion names the message.
    final empty = tester.widget<Text>(
      find.byKey(const ValueKey('download-empty')),
    );
    expect(empty.data, contains('9.99'));
  });

  testWidgets('a stale offline list warns that it may be out of date', (
    tester,
  ) async {
    await pump(tester, list: VersionListReady(_manifest(), fromCache: true));

    expect(find.textContaining('out of date'), findsOneWidget);
  });

  testWidgets('an already installed version is marked and not clickable', (
    tester,
  ) async {
    await pump(tester, installed: {'1.20.1'});

    expect(find.text('Installed'), findsOneWidget);

    await tester.tap(find.text('1.20.1'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      installs.installedCalled,
      isEmpty,
      reason: 'reinstalling an installed version must not be one click away',
    );
  });

  testWidgets('tapping a row starts that install', (tester) async {
    await pump(tester);

    await tester.tap(find.text('1.20.1'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(installs.installedCalled, ['1.20.1']);
    expect(installs.loaders, [LoaderKind.vanilla]);
  });

  testWidgets('the loader chosen in the toolbar is what gets installed', (
    tester,
  ) async {
    await pump(tester);

    // PCL's loader tab, as a segmented control next to the list.
    final fabric = find.descendant(
      of: find.byKey(const ValueKey('download-loader')),
      matching: find.text('Fabric'),
    );
    expect(fabric, findsOneWidget);
    await tester.tap(fabric);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<m3.SegmentedButton<LoaderKind>>(
            find.byKey(const ValueKey('download-loader')),
          )
          .selected,
      {LoaderKind.fabric},
    );
    await tester.tap(find.text('1.20.1'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(installs.installedCalled, ['1.20.1']);
    expect(installs.loaders, [LoaderKind.fabric]);
  });

  testWidgets('the loader switcher keeps its width when the choice moves', (
    tester,
  ) async {
    await pump(tester);
    final control = find.byKey(const ValueKey('download-loader'));
    double width() => tester.getSize(control).width;

    final atVanilla = width();
    // `SegmentedButton` sizes segments by intrinsic width and, by default, puts a
    // check mark in the selected one. Moving the selection therefore resized the
    // control, and because it sits in a `Wrap` the whole toolbar reflowed - the
    // "gaps change when I click the switcher" report.
    for (final label in ['Fabric', 'Quilt', 'Vanilla']) {
      await tester.tap(
        find.descendant(of: control, matching: find.text(label)),
      );
      await tester.pumpAndSettle();
      expect(width(), atVanilla, reason: '$label must not resize the switcher');
    }
  });

  testWidgets('a running install shows phase, bytes, speed and a cancel', (
    tester,
  ) async {
    installs.stall = true;
    await pump(tester);

    await tester.tap(find.text('1.20.1'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(m3.LinearProgressIndicator), findsOneWidget);
    expect(find.text('Downloading'), findsOneWidget);
    expect(find.text('Step 6 of 9'), findsOneWidget);
    // Preformatted sizes: the screen must not format bytes itself, because that
    // formatting is shared with the log view and the queue.
    expect(find.text('5.0 MB of 20.0 MB'), findsOneWidget);
    expect(find.text('1.0 MB/s'), findsOneWidget);

    await tester.tap(find.text('Cancel install'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(installs.cancelCalls, 1);
    expect(find.text('Install cancelled'), findsOneWidget);
  });

  testWidgets('success reports the version as ready to play', (tester) async {
    await pump(tester);

    await tester.tap(find.text('1.20.1'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('1.20.1 is ready to play'), findsOneWidget);
  });

  testWidgets('a completed install with bad files asks for repair', (
    tester,
  ) async {
    await pump(tester);
    installs.finishWithProblems('1.20.1', 3);
    await tester.pump(const Duration(milliseconds: 100));

    // "Ready to play" would be a lie: three files failed verification.
    expect(find.textContaining('3 file'), findsOneWidget);
    expect(find.textContaining('ready to play'), findsNothing);
  });

  testWidgets('a failure shows the cause and offers a retry', (tester) async {
    await pump(tester);
    installs.fail('1.20.1', 'no natives resolve for this platform');
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Download failed'), findsOneWidget);
    // The installer's own words, not a generic message.
    expect(find.text('no natives resolve for this platform'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(installs.installedCalled, ['1.20.1']);
  });

  testWidgets('closing the panel clears it', (tester) async {
    await pump(tester);
    installs.finishWithProblems('1.20.1', 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('1.20.1 is ready to play'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('1.20.1 is ready to play'), findsNothing);
  });

  testWidgets('a failed version list offers a reload', (tester) async {
    await pump(tester, list: const VersionListFailed('connection refused'));

    expect(find.text('connection refused'), findsOneWidget);
    expect(find.text('Reload'), findsOneWidget);
  });

  testWidgets('every label comes from the ARB, not the widget', (tester) async {
    // Mounting in Chinese proves the screen is not holding English literals:
    // a hardcoded string would stay English here.
    final container = ProviderContainer(
      overrides: [
        versionListProvider.overrideWith(
          () => ScriptedVersionList(VersionListReady(_manifest())),
        ),
        installControllerProvider.overrideWith(() => installs),
        installedVersionsProvider.overrideWith(
          () => ScriptedInstalled(const {'1.20.1'}),
        ),
      ],
    );
    addTearDown(container.dispose);

    await pumpScreen(
      tester,
      container,
      const DownloadScreen(),
      locale: const Locale('zh'),
      motion: Motion.none,
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 400));

    // The page title is the navigation label ("下载"), not the screen's old
    // interior heading: every page names itself the way the rail names it.
    expect(find.text('下载'), findsOneWidget);
    expect(find.text('已安装'), findsOneWidget);
    expect(find.text('Versions'), findsNothing);
    expect(find.text('Installed'), findsNothing);
  });
}
