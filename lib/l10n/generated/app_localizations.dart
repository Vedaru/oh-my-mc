import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// Product name. Deliberately not translated: it is a name, not a sentence.
  ///
  /// In en, this message translates to:
  /// **'oh my mc'**
  String get appTitle;

  /// Navigation item for the launch screen.
  ///
  /// In en, this message translates to:
  /// **'Launch'**
  String get navLaunch;

  /// Navigation item for the instance list.
  ///
  /// In en, this message translates to:
  /// **'Instances'**
  String get navInstances;

  /// Navigation item for the download screen.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get navDownload;

  /// Navigation item for the setup screen.
  ///
  /// In en, this message translates to:
  /// **'Setup'**
  String get navSetup;

  /// Navigation item for the log console.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get navLogs;

  /// Starts the selected instance.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get playButton;

  /// Stops the running game.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stopButton;

  /// Shown while the game process starts.
  ///
  /// In en, this message translates to:
  /// **'Launching…'**
  String get launching;

  /// Placeholder when the instance list is empty.
  ///
  /// In en, this message translates to:
  /// **'No instance selected'**
  String get noInstanceSelected;

  /// Creates a new instance.
  ///
  /// In en, this message translates to:
  /// **'New instance'**
  String get instanceCreate;

  /// Imports an instance from an archive.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get instanceImport;

  /// Exports an instance to an archive.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get instanceExport;

  /// Duplicates an instance.
  ///
  /// In en, this message translates to:
  /// **'Clone'**
  String get instanceClone;

  /// Deletes an instance.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get instanceDelete;

  /// Confirmation before deleting an instance.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}? This cannot be undone.'**
  String instanceDeleteConfirm(String name);

  /// Number of installed instances.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No instances} =1{1 instance} other{{count} instances}}'**
  String instanceCount(int count);

  /// Version list tab.
  ///
  /// In en, this message translates to:
  /// **'Versions'**
  String get downloadVersions;

  /// Installer tab for Forge/Fabric and friends.
  ///
  /// In en, this message translates to:
  /// **'Loaders'**
  String get downloadLoaders;

  /// Installs the selected version or loader.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get downloadInstall;

  /// Marks a version that is already installed.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get downloadInstalled;

  /// Release channel filter.
  ///
  /// In en, this message translates to:
  /// **'Release'**
  String get downloadRelease;

  /// Snapshot channel filter.
  ///
  /// In en, this message translates to:
  /// **'Snapshot'**
  String get downloadSnapshot;

  /// Old version filter.
  ///
  /// In en, this message translates to:
  /// **'Old'**
  String get downloadOld;

  /// Title of the task queue.
  ///
  /// In en, this message translates to:
  /// **'Install queue'**
  String get queueTitle;

  /// Pauses the queue.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get queuePause;

  /// Resumes the queue.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get queueResume;

  /// Cancels a task.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get queueCancel;

  /// Setup section: how the game is launched.
  ///
  /// In en, this message translates to:
  /// **'Launch'**
  String get setupLaunch;

  /// Setup section: Java runtime management.
  ///
  /// In en, this message translates to:
  /// **'Java'**
  String get setupJava;

  /// Setup section: download source and mirror.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get setupDownload;

  /// Setup section: theme, motion and language.
  ///
  /// In en, this message translates to:
  /// **'Interface'**
  String get setupUi;

  /// Memory allocation setting.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get setupMemory;

  /// Interface language setting.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get setupLanguage;

  /// Toggles UI motion.
  ///
  /// In en, this message translates to:
  /// **'Animations'**
  String get setupMotion;

  /// Light/dark/system theme choice.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get setupThemeMode;

  /// Light theme.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// Dark theme.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// Use the OS theme.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get themeSystem;

  /// Log console title.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get logsTitle;

  /// Shown before any log line arrives.
  ///
  /// In en, this message translates to:
  /// **'No log output yet'**
  String get logsEmpty;

  /// Retry a failed action.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get actionRetry;

  /// Closes a dialog.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// Generic download error title.
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get errorDownloadFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
