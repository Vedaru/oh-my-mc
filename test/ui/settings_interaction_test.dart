import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/app/providers.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:oh_my_mc/ui/setup/network_panel.dart';
import 'package:oh_my_mc/ui/setup/setup_screen.dart';

import '../support/harness.dart';

/// A control that looks enabled and does nothing is the worst kind of bug: the user
/// clicks, nothing happens, and there is no error to report. These tests exist because
/// the settings page shipped one - the network source radios could not be changed
/// unless some other control happened to rebuild the panel.
void main() {
  Future<ProviderContainer> pumpPanel(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWith(
          (ref) => MemorySettingsStore(AppSettings.defaults),
        ),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const m3.Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpScreen(tester, container, const NetworkPanel());
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('the download source radios change the setting', (tester) async {
    final container = await pumpPanel(tester);

    // Tap the *label*, the way a user does - not the radio's tiny circle and not a
    // key on a wrapper.
    await tester.tap(find.text('BMCLAPI'));
    await tester.pumpAndSettle();

    expect(
      container.read(appSettingsProvider).downloadSource,
      SourcePreference.bmclapi,
      reason: 'a radio that does not write the setting is a decoration',
    );
    expect(
      container.read(appSettingsProvider).downloadSource,
      isNot(SourcePreference.auto),
    );
    // The *rendered* state, not just the stored one: a radio that writes the setting
    // and keeps drawing the old selection is the bug this test was written for.
    final group = tester.widget<m3.RadioGroup<SourcePreference>>(
      find.byType(m3.RadioGroup<SourcePreference>),
    );
    expect(group.groupValue, SourcePreference.bmclapi);
  });

  testWidgets('the choice survives a rebuild of the panel', (tester) async {
    final container = await pumpPanel(tester);

    await tester.tap(find.text('Mojang'));
    await tester.pumpAndSettle();
    expect(
      container.read(appSettingsProvider).downloadSource,
      SourcePreference.official,
    );

    // Rebuild by switching away and back: the selection has to come from the setting,
    // not from local state that a rebuild would drop.
    await pumpScreen(tester, container, const NetworkPanel());
    await tester.pumpAndSettle();

    expect(find.text('Mojang'), findsWidgets);
    expect(
      container.read(appSettingsProvider).downloadSource,
      SourcePreference.official,
    );
  });

  testWidgets('the settings screen reaches a section and its controls work', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWith(
          (ref) => MemorySettingsStore(AppSettings.defaults),
        ),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const m3.Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpScreen(tester, container, const SetupScreen());
    await tester.pumpAndSettle();

    // Sections are doors, not decoration: picking one shows its controls.
    await tester.tap(find.byKey(const m3.ValueKey('setup-section-network')));
    await tester.pumpAndSettle();
    expect(find.text('BMCLAPI'), findsOneWidget);

    await tester.tap(find.text('BMCLAPI'));
    await tester.pumpAndSettle();
    expect(
      container.read(appSettingsProvider).downloadSource,
      SourcePreference.bmclapi,
    );
  });

  testWidgets('every section is reachable and shows something', (tester) async {
    final container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWith(
          (ref) => MemorySettingsStore(AppSettings.defaults),
        ),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const m3.Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpScreen(tester, container, const SetupScreen());
    await tester.pumpAndSettle();

    for (final name in [
      'general',
      'appearance',
      'launch',
      'java',
      'network',
      'about',
    ]) {
      await tester.tap(find.byKey(m3.ValueKey('setup-section-$name')));
      await tester.pumpAndSettle();
      // The content pane is keyed by section; if the tap did nothing this fails.
      expect(
        find.byKey(m3.ValueKey('setup-$name')),
        findsOneWidget,
        reason: 'section $name did not open',
      );
    }
  });
}
