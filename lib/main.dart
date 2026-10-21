import 'package:fluent_ui/fluent_ui.dart';

import 'l10n/l10n.dart';
import 'ui/motion/motion.dart';
import 'ui/theme/app_theme.dart';

void main() {
  runApp(const OhMyMcApp());
}

class OhMyMcApp extends StatelessWidget {
  const OhMyMcApp({super.key, this.locale, this.themeMode = ThemeMode.system});

  /// Forces a locale instead of following the OS. Used by tests and, later, by
  /// the language picker in `/setup`.
  final Locale? locale;

  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) {
    return MotionScope(
      motion: Motion.full,
      child: FluentApp(
        // Localized via onGenerateTitle rather than a plain string: the window
        // title has to change when the user switches language, and `title` is
        // only read once.
        onGenerateTitle: (context) => context.l10n.appTitle,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        locale: locale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        // Placeholder body: the real shell (navigation, title bar, page
        // transitions) is M3.4. It exists so the localization and theme wiring is
        // exercised by the running app, not only by tests.
        home: Builder(
          builder: (context) => NavigationView(
            content: Center(child: Text(context.l10n.appTitle)),
          ),
        ),
      ),
    );
  }
}
