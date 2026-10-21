import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:fluent_ui/fluent_ui.dart';

import 'generated/app_localizations.dart';

export 'generated/app_localizations.dart';

/// The app's supported locales, in the order the language picker lists them.
///
/// Only `zh` (Simplified) is shipped. Fluent falls back to its own `zh` bundle
/// for `zh_Hans`, which is what we want; a `zh_Hant` user is therefore served
/// Simplified Chinese rather than English, which is the more useful failure.
const appSupportedLocales = <Locale>[Locale('en'), Locale('zh')];

/// Localization delegates for the app shell.
///
/// Deliberately not `AppLocalizations.localizationsDelegates`: that list also
/// installs `GlobalMaterialLocalizations` and `GlobalCupertinoLocalizations`,
/// whose types come from the in-SDK Material copy. This app's Material widgets
/// come from `material_ui` (a separate package with its own, incompatible
/// `MaterialLocalizations`), and `FluentApp` installs `FluentLocalizations`
/// itself. Registering the SDK delegates would add a third localization tree
/// that nothing reads.
const appLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  FluentLocalizations.delegate,
];

/// Shorthand for `AppLocalizations.of(context)`.
///
/// The generated accessor throws when no [AppLocalizations] is in scope, which is
/// the behaviour we want: a missing delegate is a wiring bug, not a condition to
/// degrade gracefully from - a silently-untranslated UI would pass every test.
extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
