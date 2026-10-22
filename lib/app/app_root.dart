import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../data/settings.dart';
import '../l10n/l10n.dart';
import '../ui/motion/motion.dart';
import '../ui/theme/app_theme.dart';
import 'providers.dart';
import 'router.dart';

/// Presents a route. Supplied by the shell once the shell exists; until then the
/// app root renders the route directly.
typedef ScreenBuilder = Widget Function(
  BuildContext context,
  GoRouterState state,
);

/// The composition root: settings in, themed and localized subtree out.
///
/// Everything a user can change on `/setup` is resolved here and nowhere else:
///
///  * [AppSettings.theme] -> `MaterialApp.themeMode`
///  * [AppSettings.language] -> `MaterialApp.locale`, `null` meaning "follow the OS"
///  * [AppSettings.accent] -> the seeded `ColorScheme` of both themes
///
/// Motion is not a setting: `MotionScope` is always `Motion.full`, and only the OS
/// accessibility flag (OR'd inside `MotionScope.of`) can ever turn it off.
///
/// Keeping this in one widget is what stops a screen from reaching for a
/// `Theme.of` or a raw `Locale` and inventing a second, disagreeing answer.
class AppRoot extends ConsumerWidget {
  const AppRoot({
    required this.screens,
    this.initialLocation = Routes.launch,
    this.overrideMotion,
    super.key,
  });

  final ScreenBuilder screens;
  final String initialLocation;

  /// Forces a motion policy, for tests that want to prove both branches without
  /// going through `/setup`. Production always uses the settings value.
  final Motion? overrideMotion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final motion = overrideMotion ?? Motion.full;

    return MotionScope(
      motion: motion,
      child: _App(
        settings: settings,
        screens: screens,
        initialLocation: initialLocation,
      ),
    );
  }
}

/// Rebuilds [MaterialApp] when the router is replaced. `MaterialApp.router`
/// takes a `RouterConfig`, and a theme change must not recreate it - otherwise
/// every settings change would reset navigation to the initial location.
class _App extends StatefulWidget {
  const _App({
    required this.settings,
    required this.screens,
    required this.initialLocation,
  });

  final AppSettings settings;
  final ScreenBuilder screens;
  final String initialLocation;

  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  late GoRouter _router = _buildRouter();

  GoRouter _buildRouter() => createRouter(
    screens: widget.screens,
    initialLocation: widget.initialLocation,
  );

  @override
  void didUpdateWidget(_App oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only a changed *screen builder* invalidates the router. Theme, locale and
    // motion changes flow through MaterialApp's own configuration.
    if (oldWidget.screens != widget.screens ||
        oldWidget.initialLocation != widget.initialLocation) {
      _router = _buildRouter();
    }
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return m3.MaterialApp.router(
      routerConfig: _router,
      title: 'oh my mc',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.material(
        Brightness.light,
        accent: widget.settings.accent,
      ),
      darkTheme: AppTheme.material(
        Brightness.dark,
        accent: widget.settings.accent,
      ),
      themeMode: switch (widget.settings.theme) {
        ThemePreference.system => m3.ThemeMode.system,
        ThemePreference.light => m3.ThemeMode.light,
        ThemePreference.dark => m3.ThemeMode.dark,
      },
      // `null` hands the decision to the platform, which is what "system" means
      // for language.
      locale: switch (widget.settings.language) {
        LanguagePreference.system => null,
        LanguagePreference.english => const Locale('en'),
        LanguagePreference.chinese => const Locale('zh'),
      },
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
    );
  }
}
