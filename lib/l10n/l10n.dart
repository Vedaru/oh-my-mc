import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;

import 'generated/app_localizations.dart';

export 'generated/app_localizations.dart';

/// The app's supported locales, in the order the language picker lists them.
///
/// Only `zh` (Simplified) is shipped. `MaterialApp` negotiates `zh_Hant` down to
/// `zh`, so a Traditional Chinese user is served Simplified rather than English,
/// which is the more useful failure.
const appSupportedLocales = <Locale>[Locale('en'), Locale('zh')];

/// Localization delegates for the whole app.
///
/// Deliberately not `AppLocalizations.localizationsDelegates`: that list is
/// generated against the in-SDK Material localizations, whose types are
/// incompatible with `material_ui`'s. Registering it would add a second
/// localization tree that nothing reads.
///
/// The Material half comes from `material_ui`'s own
/// [m3.GlobalMaterialLocalizations], and it must be the **plural** `delegates`
/// list. `MaterialApp` asserts that every delegate covers the active locale, so
/// registering `GlobalMaterialLocalizations.delegate` alone throws
/// "locale zh is not supported by all localization delegates" as soon as a
/// Chinese user opens the app - the Cupertino delegate is what is missing.
const appLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  ...m3.GlobalMaterialLocalizations.delegates,
];

/// Shorthand for `AppLocalizations.of(context)`.
///
/// The generated accessor throws when no [AppLocalizations] is in scope, which is
/// the behaviour we want: a missing delegate is a wiring bug, not a condition to
/// degrade gracefully from - a silently-untranslated UI would pass every test.
extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
