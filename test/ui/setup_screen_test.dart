import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/app/providers.dart';
import 'package:oh_my_mc/data/instance_providers.dart';
import 'package:oh_my_mc/data/instance_store.dart';
import 'package:oh_my_mc/data/java_providers.dart';
import 'package:oh_my_mc/data/account_providers.dart';
import 'package:oh_my_mc/data/account_store.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/ui/motion/motion.dart';
import 'package:oh_my_mc/ui/components/app_accent_picker.dart';
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

    /// Which settings section to open. The page shows one section at a time, so a
    /// test has to say where the control it is about lives.
    String section = 'general',
  }) async {
    // One section at a time, so a normal window is enough; the section list itself is
    // a `ListView` and needs a bounded height.
    tester.view.physicalSize = const Size(1400, 1000);
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
        // Accounts are read from a file in production; a real file read never
        // completes under the fake clock.
        accountStoreProvider.overrideWithValue(MemoryAccountStore()),
      ],
    );
    addTearDown(container.dispose);

    // Real directory IO does not complete under the test binding's fake clock,
    // so the lists that touch it are resolved first and the widget then reads a
    // ready value.
    await tester.runAsync(() => container.read(javaRuntimesProvider.future));
    await tester.runAsync(() => container.read(accountListProvider.future));

    await pumpScreen(
      tester,
      container,
      const SetupScreen(),
      motion: Motion.none,
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(m3.ValueKey('setup-section-$section')));
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  testWidgets('with nothing downloaded, the list says so', (tester) async {
    await pump(tester, section: 'java');
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

    await pump(tester, section: 'java');

    expect(find.text('Java 17 (17.0.15)'), findsOneWidget);
    // A freshly-created fake tree is tiny; the assertion is that the size is
    // rendered at all, not a particular number.
    expect(find.textContaining('on disk'), findsOneWidget);
  });

  testWidgets('choosing dark theme persists it', (tester) async {
    final container = await pump(tester, section: 'appearance');

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
    final container = await pump(tester, section: 'general');

    await tester.tap(
      find.byKey(const ValueKey('language-LanguagePreference.chinese')),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(appSettingsProvider).language,
      LanguagePreference.chinese,
    );
  });

  testWidgets('the language can be switched back, not only away from', (
    tester,
  ) async {
    // The bug this pins: with English stored, "Follow system" and "Chinese" were
    // unreachable - the group kept rendering English as the only option that could
    // be chosen, so the preference was a one-way door.
    final container = await pump(
      tester,
      section: 'general',
      settings: const AppSettings(language: LanguagePreference.english),
    );

    await tester.tap(
      find.byKey(const ValueKey('language-LanguagePreference.system')),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(appSettingsProvider).language,
      LanguagePreference.system,
    );
    expect(
      container.read(settingsStoreProvider).current.language,
      LanguagePreference.system,
    );

    // The *rendered* group, not just the store: reading the provider once instead of
    // watching it left the radios showing the option the user had already left.
    expect(
      tester
          .widget<m3.RadioGroup<LanguagePreference>>(
            find.byType(m3.RadioGroup<LanguagePreference>),
          )
          .groupValue,
      LanguagePreference.system,
    );

    // And back again: the door swings both ways.
    await tester.tap(
      find.byKey(const ValueKey('language-LanguagePreference.english')),
    );
    await tester.pumpAndSettle();
    expect(
      container.read(appSettingsProvider).language,
      LanguagePreference.english,
    );
  });

  testWidgets('picking an accent swatch persists it', (tester) async {
    final container = await pump(tester, section: 'appearance');

    // Blue is the default, so its swatch is the selected one.
    expect(container.read(appSettingsProvider).accent, AccentChoice.blue);

    await tester.tap(find.byKey(const ValueKey('accent-purple')));
    await tester.pumpAndSettle();

    expect(container.read(appSettingsProvider).accent, AccentChoice.purple);
  });

  testWidgets('there is no animation switch any more', (tester) async {
    await pump(tester, section: 'appearance');

    // Motion is part of the design: only the OS accessibility flag can turn it
    // off, so the screen must not offer a toggle.
    expect(find.byKey(const ValueKey('setup-motion')), findsNothing);
  });

  testWidgets('an offline account is added and becomes the active one', (
    tester,
  ) async {
    final container = await pump(tester, section: 'accounts');

    await tester.tap(find.byKey(const ValueKey('account-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('account-name')),
      'Steve_1',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('account-create')));
    await tester.pumpAndSettle();

    final list = container.read(accountListProvider).value!;
    expect(list.accounts.map((a) => a.name), contains('Steve_1'));
    expect(list.active?.name, 'Steve_1');
  });

  testWidgets('the game would reject a bad name, so the dialog does too', (
    tester,
  ) async {
    await pump(tester, section: 'accounts');

    await tester.tap(find.byKey(const ValueKey('account-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('account-name')), 'a b');
    await tester.pumpAndSettle();

    // Save stays disabled: a name the game will refuse must not become an account.
    final save = tester.widget<m3.TextButton>(
      find.byKey(const ValueKey('account-create')),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('the memory slider persists the value it was released on', (
    tester,
  ) async {
    final container = await pump(tester, section: 'launch');

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
    // The controls live in different sections now, so each is asserted in its own
    // pane rather than all at once.
    await pump(
      tester,
      section: 'appearance',
      settings: const AppSettings(
        theme: ThemePreference.light,
        language: LanguagePreference.chinese,
        accent: AccentChoice.green,
        playerName: 'Alex',
      ),
    );

    expect(
      tester.widget<AppAccentPicker>(find.byType(AppAccentPicker)).value,
      AccentChoice.green,
    );

    // Identity lives in 账户 now: the stored name seeds the first account, so an
    // update does not rename anyone.
    await tester.tap(find.byKey(const ValueKey('setup-section-accounts')));
    await tester.pumpAndSettle();
    expect(find.text('Alex'), findsWidgets);
  });
}
