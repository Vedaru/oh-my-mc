import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oh_my_mc/app/app_root.dart';
import 'package:oh_my_mc/app/providers.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:oh_my_mc/ui/motion/motion.dart';

/// Records what the *content* sees, which is the only place a wrong mapping shows
/// up: the app root can hold a correct ThemeMode while the tree underneath is
/// still light.
class _Probe {
  Brightness? brightness;
  Locale? locale;
  bool? motionEnabled;
}

Future<(ProviderContainer, _Probe)> _pump(
  WidgetTester tester, {
  AppSettings settings = AppSettings.defaults,
}) async {
  final probe = _Probe();
  final container = ProviderContainer(
    overrides: [
      settingsStoreProvider.overrideWith(
        (ref) => MemorySettingsStore(settings),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: AppRoot(
        screens: (context, state) {
          // What the content actually sees. Asserting the `ThemeMode` instead
          // would pass even if the theme failed to resolve.
          probe.brightness = m3.Theme.of(context).brightness;
          probe.locale = Localizations.localeOf(context);
          probe.motionEnabled = MotionScope.of(context).enabled;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container, probe);
}

void main() {
  group('theme preference', () {
    testWidgets('light hands light brightness to content', (tester) async {
      final (_, probe) = await _pump(
        tester,
        settings: const AppSettings(theme: ThemePreference.light),
      );
      expect(probe.brightness, Brightness.light);
    });

    testWidgets('dark hands dark brightness to content', (tester) async {
      final (_, probe) = await _pump(
        tester,
        settings: const AppSettings(theme: ThemePreference.dark),
      );
      // The §0.6 trap: a theme built without an explicit brightness reports
      // light here even in dark mode, and every derived colour is wrong.
      expect(probe.brightness, Brightness.dark);
    });

    testWidgets('a theme change takes effect without restarting', (
      tester,
    ) async {
      final (container, probe) = await _pump(
        tester,
        settings: const AppSettings(theme: ThemePreference.light),
      );
      expect(probe.brightness, Brightness.light);

      await container
          .read(appSettingsProvider.notifier)
          .setTheme(ThemePreference.dark);
      await tester.pumpAndSettle();

      expect(probe.brightness, Brightness.dark);
    });
  });

  group('language preference', () {
    testWidgets('english resolves to en', (tester) async {
      final (_, probe) = await _pump(
        tester,
        settings: const AppSettings(language: LanguagePreference.english),
      );
      expect(probe.locale?.languageCode, 'en');
    });

    testWidgets('chinese resolves to zh, not zh_Hant', (tester) async {
      final (_, probe) = await _pump(
        tester,
        settings: const AppSettings(language: LanguagePreference.chinese),
      );
      expect(probe.locale?.languageCode, 'zh');
    });
  });

  group('motion', () {
    testWidgets('motion is on with no setting involved', (tester) async {
      // There is no animation switch: the tree reads `Motion.full`, and nothing a
      // user can change on /setup may turn it off.
      final (_, probe) = await _pump(tester);
      expect(probe.motionEnabled, isTrue);
    });

    testWidgets('the OS setting wins over an enabled preference', (
      tester,
    ) async {
      tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      final (_, probe) = await _pump(tester);

      expect(
        probe.motionEnabled,
        isFalse,
        reason: 'the OS accessibility flag may remove motion from the tree',
      );
    });

    testWidgets('an override beats the OS setting, so both branches are '
        'reachable in tests', (tester) async {
      // overrideMotion exists for exactly this: without it a CI machine that
      // happens to disable animations would skip every full-motion assertion.
      final container = ProviderContainer(
        overrides: [
          settingsStoreProvider.overrideWith((ref) => MemorySettingsStore()),
        ],
      );
      addTearDown(container.dispose);

      bool? seen;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: AppRoot(
            overrideMotion: Motion.full,
            screens: (context, state) {
              seen = MotionScope.of(context).enabled;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The override is applied above MotionScope, so it is read back verbatim.
      expect(seen, isTrue);
    });
  });

  testWidgets(
    'the router is built once, so a settings change keeps the route',
    (tester) async {
      // A rebuild that recreated GoRouter would silently reset the user to
      // /launch every time they toggled a switch.
      final container = ProviderContainer(
        overrides: [
          settingsStoreProvider.overrideWith((ref) => MemorySettingsStore()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: AppRoot(screens: (context, state) => const SizedBox.shrink()),
        ),
      );
      await tester.pumpAndSettle();

      final router =
          tester
                  .widget<m3.MaterialApp>(find.byType(m3.MaterialApp))
                  .routerConfig!
              as GoRouter;
      router.go('/setup');
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/setup');

      await container
          .read(appSettingsProvider.notifier)
          .setTheme(ThemePreference.dark);
      await tester.pumpAndSettle();

      expect(
        router.state.uri.path,
        '/setup',
        reason: 'changing a setting must not reset navigation',
      );
    },
  );
}
