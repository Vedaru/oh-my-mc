import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart' as m3e;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/app/providers.dart';
import 'package:oh_my_mc/data/instance_providers.dart';
import 'package:oh_my_mc/data/instance_store.dart';
import 'package:oh_my_mc/data/java_providers.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/ui/motion/motion.dart';
import 'package:oh_my_mc/ui/setup/setup_screen.dart';
import '../support/harness.dart';
import 'package:path/path.dart' as p;

/// The setup screen, asserted against the stores rather than the pixels.
///
/// Its runtime list reads the real filesystem, so these tests use a real temp
/// tree: the point of that half of the screen is what it does with what is
/// actually installed. The settings half asserts that a change reaches the disk,
/// because a toggle that only moves is the placeholder this replaced.
void main() {
  late Directory data;

  setUp(() async {
    data = await Directory.systemTemp.createTemp('ommc-setup-');
  });

  tearDown(() async {
    if (await data.exists()) await data.delete(recursive: true);
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    AppSettings settings = AppSettings.defaults,
  }) async {
    // The page is taller than the default 600px test viewport now that it has a
    // Java-management section, and `ListView` does not build off-screen
    // children. A taller viewport asserts the whole page instead of scrolling
    // to each row, which would hide a row that never renders at all.
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        launcherPathsProvider.overrideWithValue(
          LauncherPaths(data: data, game: Directory(p.join(data.path, 'game'))),
        ),
        settingsStoreProvider.overrideWith(
          (ref) => MemorySettingsStore(settings),
        ),
        instanceStoreProvider.overrideWith(
          (ref) => MemoryInstanceStore(const []),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Real directory IO does not complete under the test binding's fake clock,
    // so the list is resolved first and the widget then reads a ready value.
    await tester.runAsync(() => container.read(javaRuntimesProvider.future));

    await pumpScreen(
      tester,
      container,
      const SetupScreen(),
      motion: Motion.none,
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  testWidgets('with nothing downloaded, the list says so', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('java-list-empty')), findsOneWidget);
  });

  testWidgets('a downloaded runtime is listed with its major and disk use', (
    tester,
  ) async {
    final root = Directory(
      p.join(data.path, 'runtimes', 'java-runtime-gamma-17.0.15'),
    );
    File(p.join(root.path, 'bin', 'java'))
      ..createSync(recursive: true)
      ..writeAsStringSync('#!/bin/sh\n');

    await pump(tester);

    expect(find.text('Java 17 (17.0.15)'), findsOneWidget);
    // A freshly-created fake tree is tiny; the assertion is that the size is
    // rendered at all, not a particular number.
    expect(find.textContaining('on disk'), findsOneWidget);
  });

  testWidgets('choosing dark theme persists it', (tester) async {
    final container = await pump(tester);

    await tester.tap(find.byKey(const ValueKey('theme-ThemePreference.dark')));
    await tester.pumpAndSettle();

    // Persisted, not just held: a setting that resets on restart is the reason
    // this page used to be a stub.
    expect(container.read(appSettingsProvider).theme, ThemePreference.dark);
    expect(
      container.read(settingsStoreProvider).current.theme,
      ThemePreference.dark,
    );
  });

  testWidgets('choosing Chinese persists it', (tester) async {
    final container = await pump(tester);

    await tester.tap(
      find.byKey(const ValueKey('language-LanguagePreference.chinese')),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(appSettingsProvider).language,
      LanguagePreference.chinese,
    );
  });

  testWidgets('the animation switch flips and persists', (tester) async {
    final container = await pump(tester);

    expect(find.text('Animations on'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('setup-motion')));
    await tester.pumpAndSettle();

    expect(container.read(appSettingsProvider).uiAnimations, isFalse);
    expect(find.text('Animations off'), findsOneWidget);
  });

  testWidgets('a valid player name is stored', (tester) async {
    final container = await pump(tester);

    await tester.enterText(
      find.byKey(const ValueKey('setup-player-name')),
      'Steve_1',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(container.read(appSettingsProvider).playerName, 'Steve_1');
  });

  testWidgets('an invalid player name reverts instead of being stored', (
    tester,
  ) async {
    final container = await pump(tester);

    // Too short and containing a space: the game would reject it, and the store
    // would silently substitute "Player", which reads as a lost edit.
    await tester.enterText(
      find.byKey(const ValueKey('setup-player-name')),
      'a b',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(container.read(appSettingsProvider).playerName, 'Player');
    final field = tester.widget<m3e.M3ETextField>(
      find.byKey(const ValueKey('setup-player-name')),
    );
    expect(field.controller!.text, 'Player');
  });

  testWidgets('the memory slider persists the value it was released on', (
    tester,
  ) async {
    final container = await pump(tester);

    await tester.drag(
      find.byKey(const ValueKey('setup-memory')),
      const Offset(60, 0),
    );
    await tester.pumpAndSettle();

    final memory = container.read(appSettingsProvider).memoryMb;
    expect(memory, greaterThan(AppSettings.defaultMemoryMb));
    expect(memory % 512, 0, reason: 'the slider snaps to 512 MB steps');
  });

  testWidgets('the controls start from the stored settings', (tester) async {
    await pump(
      tester,
      settings: const AppSettings(
        theme: ThemePreference.light,
        language: LanguagePreference.chinese,
        uiAnimations: false,
        playerName: 'Alex',
      ),
    );

    expect(find.text('Animations off'), findsOneWidget);
    final field = tester.widget<m3e.M3ETextField>(
      find.byKey(const ValueKey('setup-player-name')),
    );
    expect(field.controller!.text, 'Alex');
  });
}
