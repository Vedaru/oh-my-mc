import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/core/update/update_check.dart';
import 'package:oh_my_mc/ui/setup/about_panel.dart';

import '../support/harness.dart';

/// A checker with a scripted answer, so the panel's three outcomes are testable
/// without talking to GitHub. The feed parsing lives in
/// `test/core/update/update_check_test.dart`.
class _ScriptedChecker extends UpdateChecker {
  _ScriptedChecker(this.answer);

  final UpdateCheck? answer;
  var calls = 0;

  @override
  Future<UpdateCheck?> check({required String currentVersion}) async {
    calls++;
    return answer;
  }
}

void main() {
  Future<_ScriptedChecker> pump(
    WidgetTester tester,
    UpdateCheck? answer,
  ) async {
    final checker = _ScriptedChecker(answer);
    final container = ProviderContainer(
      overrides: [updateCheckerProvider.overrideWithValue(checker)],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpScreen(tester, container, const AboutPanel());
    await tester.pumpAndSettle();
    return checker;
  }

  testWidgets('nothing about updates until asked', (tester) async {
    final checker = await pump(tester, null);

    expect(find.byKey(const m3.ValueKey('about-version')), findsOneWidget);
    // The check is a request to a third party: it does not happen on open.
    expect(checker.calls, 0);
    expect(find.textContaining('is available'), findsNothing);
  });

  testWidgets('a newer release offers the installer, not just the notes', (
    tester,
  ) async {
    await pump(
      tester,
      const UpdateCheck(
        isNewer: true,
        latest: ReleaseInfo(
          version: '0.2.0',
          title: '0.2.0',
          notes: '- mods install with dependencies',
          pageUrl: 'https://example.invalid/v0.2.0',
          installerUrl: 'https://example.invalid/setup.exe',
        ),
      ),
    );

    await tester.tap(find.byKey(const m3.ValueKey('about-check')));
    await tester.pumpAndSettle();

    expect(find.textContaining('0.2.0'), findsWidgets);
    expect(find.textContaining('dependencies'), findsOneWidget);
    // The whole point: a button that downloads the .exe.
    expect(find.byKey(const m3.ValueKey('about-download')), findsOneWidget);
  });

  testWidgets('a release without an installer does not offer a download', (
    tester,
  ) async {
    await pump(
      tester,
      const UpdateCheck(
        isNewer: true,
        latest: ReleaseInfo(
          version: '0.2.0',
          title: '',
          notes: '',
          pageUrl: 'https://example.invalid/v0.2.0',
        ),
      ),
    );

    await tester.tap(find.byKey(const m3.ValueKey('about-check')));
    await tester.pumpAndSettle();

    expect(find.byKey(const m3.ValueKey('about-download')), findsNothing);
    expect(find.text('Release notes'), findsOneWidget);
  });

  testWidgets('being up to date says so', (tester) async {
    await pump(
      tester,
      const UpdateCheck(
        isNewer: false,
        latest: ReleaseInfo(
          version: '0.1.0',
          title: '',
          notes: '',
          pageUrl: '',
        ),
      ),
    );

    await tester.tap(find.byKey(const m3.ValueKey('about-check')));
    await tester.pumpAndSettle();

    expect(find.textContaining('is the newest version'), findsOneWidget);
  });

  testWidgets('an unreachable feed blames the feed, not the install', (
    tester,
  ) async {
    await pump(tester, null);

    await tester.tap(find.byKey(const m3.ValueKey('about-check')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not reach'), findsOneWidget);
    expect(find.textContaining('is available'), findsNothing);
  });
}
