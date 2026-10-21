import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app/app_root.dart';
import 'app/providers.dart';
import 'app/router.dart';
import 'data/prefs_settings_store.dart';
import 'data/settings.dart';
import 'l10n/l10n.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = PrefsSettingsStore();
  // Awaited before the first frame so the app never paints in the wrong language
  // or theme and then flips.
  await store.init();

  runApp(OhMyMcApp(store: store));
}

/// The app entry widget.
///
/// Takes the [SettingsStore] by injection rather than constructing it, so a test
/// can mount the real widget tree with [MemorySettingsStore] and no platform
/// plugin. [locale] and [themeMode] pre-seed the store for tests; production
/// reads them from settings so `/setup` can change them.
class OhMyMcApp extends StatelessWidget {
  const OhMyMcApp({
    super.key,
    this.store,
    this.locale,
    this.themeMode,
    this.initialLocation = Routes.launch,
  });

  final SettingsStore? store;
  final Locale? locale;
  final ThemeMode? themeMode;
  final String initialLocation;

  @override
  Widget build(BuildContext context) {
    final settingsStore = store ?? _seededFromArguments();

    return ProviderScope(
      overrides: [settingsStoreProvider.overrideWith((ref) => settingsStore)],
      child: AppRoot(
        initialLocation: initialLocation,
        screens: (context, state) => _RoutePlaceholder(state: state),
      ),
    );
  }

  /// Builds an in-memory store from [locale]/[themeMode].
  ///
  /// Exists so tests that mount `OhMyMcApp(locale: ...)` need no platform plugin;
  /// a real launch passes [store].
  MemorySettingsStore _seededFromArguments() {
    return MemorySettingsStore(
      AppSettings(
        theme: switch (themeMode) {
          ThemeMode.light => ThemePreference.light,
          ThemeMode.dark => ThemePreference.dark,
          _ => ThemePreference.system,
        },
        language: switch (locale?.languageCode) {
          'zh' => LanguagePreference.chinese,
          'en' => LanguagePreference.english,
          _ => LanguagePreference.system,
        },
      ),
    );
  }
}

/// What every route renders until the real screens exist (M3.4.5+).
///
/// Deliberately unstyled: the user owns visual decisions, so this only proves the
/// route resolved and the localization tree is reachable from inside a page.
class _RoutePlaceholder extends StatelessWidget {
  const _RoutePlaceholder({required this.state});

  final GoRouterState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return NavigationView(
      content: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.appTitle),
            const SizedBox(height: 8),
            Text(routeTitle(l10n, state.uri.path)),
          ],
        ),
      ),
    );
  }
}
