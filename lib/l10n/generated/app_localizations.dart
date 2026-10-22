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

  /// Shown on an instance card that has never been launched.
  ///
  /// In en, this message translates to:
  /// **'Never played'**
  String get instanceNeverPlayed;

  /// Placeholder in the new-instance name field.
  ///
  /// In en, this message translates to:
  /// **'Name this instance'**
  String get instanceNameHint;

  /// Shown when the user has no instances at all.
  ///
  /// In en, this message translates to:
  /// **'No instances yet'**
  String get instancesEmpty;

  /// Shown when part of the instance file was unreadable.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 instance could not be read and was skipped} other{{count} instances could not be read and were skipped}}'**
  String instancesSkipped(int count);

  /// Dismisses a dialog without doing anything.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// Java could not be started as a process.
  ///
  /// In en, this message translates to:
  /// **'Could not start Java. Check the Java setting.'**
  String get launchFailedSpawn;

  /// A launch was refused before any process started, e.g. no Java runtime or missing files. The specific reason is in the log and, when it is fixable, in the panel above.
  ///
  /// In en, this message translates to:
  /// **'Launch refused. See the log for the reason.'**
  String get launchFailedRefused;

  /// Preparing the command line failed; details are in the log.
  ///
  /// In en, this message translates to:
  /// **'Could not prepare the launch. See the log.'**
  String get launchFailedPrepare;

  /// Shown after a session ends.
  ///
  /// In en, this message translates to:
  /// **'Exited with code {code} after {duration}'**
  String launchExited(int code, String duration);

  /// Shown on a destination whose screen is not implemented yet.
  ///
  /// In en, this message translates to:
  /// **'This screen is not built yet'**
  String get screenNotReady;

  /// Placeholder in the version search box.
  ///
  /// In en, this message translates to:
  /// **'Search versions'**
  String get downloadSearchHint;

  /// Shown when the version search box filters out every row.
  ///
  /// In en, this message translates to:
  /// **'No version matches “{query}”'**
  String downloadSearchEmpty(String query);

  /// Title of the install progress panel; the version is a Minecraft version id such as 1.20.1.
  ///
  /// In en, this message translates to:
  /// **'Installing {version}'**
  String downloadInstalling(String version);

  /// Install progress step: fetching the version manifest.
  ///
  /// In en, this message translates to:
  /// **'Reading version list'**
  String get downloadPhaseManifest;

  /// Install progress step: fetching the version JSON.
  ///
  /// In en, this message translates to:
  /// **'Reading version metadata'**
  String get downloadPhaseVersionJson;

  /// Install progress step: fetching parent versions a modded version inherits from.
  ///
  /// In en, this message translates to:
  /// **'Reading inherited metadata'**
  String get downloadPhaseParents;

  /// Install progress step: fetching the asset index.
  ///
  /// In en, this message translates to:
  /// **'Reading asset index'**
  String get downloadPhaseAssetIndex;

  /// Install progress step: planning the file set. Runs before any byte is fetched.
  ///
  /// In en, this message translates to:
  /// **'Working out what to download'**
  String get downloadPhasePlanning;

  /// Install progress step: transferring files.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get downloadPhaseDownload;

  /// Install progress step: extracting native (.dll/.so/.dylib) archives.
  ///
  /// In en, this message translates to:
  /// **'Unpacking native libraries'**
  String get downloadPhaseNatives;

  /// Install progress step: materializing legacy asset layouts.
  ///
  /// In en, this message translates to:
  /// **'Placing assets'**
  String get downloadPhaseAssets;

  /// Install progress step: checking every file the install planned is present.
  ///
  /// In en, this message translates to:
  /// **'Verifying files'**
  String get downloadPhaseVerify;

  /// Position within the install pipeline, shown next to the progress bar.
  ///
  /// In en, this message translates to:
  /// **'Step {step} of {steps}'**
  String downloadStepOf(int step, int steps);

  /// Bytes downloaded so far, out of the total. Both are preformatted sizes like "12.3 MB".
  ///
  /// In en, this message translates to:
  /// **'{done} of {total}'**
  String downloadBytes(String done, String total);

  /// Download speed. The rate is preformatted, e.g. "3.4 MB".
  ///
  /// In en, this message translates to:
  /// **'{rate}/s'**
  String downloadRate(String rate);

  /// Shown after a successful install.
  ///
  /// In en, this message translates to:
  /// **'{version} is ready to play'**
  String downloadComplete(String version);

  /// Shown when the install finished but verification found missing or corrupt files.
  ///
  /// In en, this message translates to:
  /// **'{version} installed, but {count} file(s) need repair'**
  String downloadCompleteWithProblems(String version, int count);

  /// Button that stops a running install.
  ///
  /// In en, this message translates to:
  /// **'Cancel install'**
  String get downloadCancel;

  /// Shown after the user cancels an install.
  ///
  /// In en, this message translates to:
  /// **'Install cancelled'**
  String get downloadCancelled;

  /// Download source option: Mojang servers.
  ///
  /// In en, this message translates to:
  /// **'Official'**
  String get downloadSourceOfficial;

  /// Download source option: a community mirror for mainland China. BMCLAPI is a proper name and stays untranslated.
  ///
  /// In en, this message translates to:
  /// **'BMCLAPI mirror'**
  String get downloadSourceBmclapi;

  /// Toggle that includes snapshot versions in the version list.
  ///
  /// In en, this message translates to:
  /// **'Show snapshots'**
  String get downloadShowSnapshots;

  /// Shown when the network failed and the cached version list is being used.
  ///
  /// In en, this message translates to:
  /// **'Offline — this version list may be out of date'**
  String get downloadStaleCache;

  /// Button that retries loading the version list.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get downloadRetry;

  /// Title of the panel that offers to download a Java runtime. {major} is the Java major version, e.g. 17.
  ///
  /// In en, this message translates to:
  /// **'Java {major} is required'**
  String javaDownloadTitle(int major);

  /// Explains why a Java download is being offered. {major} is the Java major version.
  ///
  /// In en, this message translates to:
  /// **'This version needs Java {major}, and it was not found on this computer.'**
  String javaDownloadWhy(int major);

  /// Button that starts downloading and installing a Java runtime. {major} is the Java major version.
  ///
  /// In en, this message translates to:
  /// **'Download and install'**
  String javaDownloadAction(int major);

  /// Progress line while downloading a Java runtime. {done} and {total} are already-formatted byte amounts, e.g. "12 MB".
  ///
  /// In en, this message translates to:
  /// **'{done} / {total}'**
  String javaDownloadProgress(String done, String total);

  /// Shown while a downloaded Java runtime is being extracted.
  ///
  /// In en, this message translates to:
  /// **'Unpacking…'**
  String get javaDownloadExtracting;

  /// Shown after a Java runtime was installed successfully. {major} is the Java major version.
  ///
  /// In en, this message translates to:
  /// **'Java {major} is ready'**
  String javaDownloadDone(int major);

  /// Shown when a Java runtime cannot be resolved because the version is not installed.
  ///
  /// In en, this message translates to:
  /// **'Install this version first; the launcher needs its version file to know which Java it asks for.'**
  String get javaUnavailableVersionMissing;

  /// Shown when the Java runtime catalogue could not be downloaded.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the Java runtime catalogue. Check the connection, then try again.'**
  String get javaUnavailableNoCatalog;

  /// Shown when the catalogue has no runtime this platform can run. {major} is the Java major version; {platform} is the platform key such as mac-os-arm64.
  ///
  /// In en, this message translates to:
  /// **'No Java {major} build is published for this system ({platform}). Install one manually.'**
  String javaUnavailableNoBuild(int major, String platform);

  /// Heading of the list of Java runtimes the launcher downloaded itself.
  ///
  /// In en, this message translates to:
  /// **'Downloaded Java runtimes'**
  String get javaManagedTitle;

  /// Shown when the launcher has downloaded no Java runtimes.
  ///
  /// In en, this message translates to:
  /// **'No Java runtimes downloaded yet.'**
  String get javaManagedEmpty;

  /// One downloaded runtime. {major} is the Java major version; {version} is the vendor build string, e.g. 17.0.15.
  ///
  /// In en, this message translates to:
  /// **'Java {major} ({version})'**
  String javaManagedItem(int major, String version);

  /// Disk usage of one downloaded runtime. {size} is an already-formatted byte amount.
  ///
  /// In en, this message translates to:
  /// **'{size} on disk'**
  String javaManagedDiskUse(String size);

  /// Button that deletes a downloaded Java runtime.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get javaDelete;

  /// Confirmation before deleting a downloaded runtime. {major} is the Java major version.
  ///
  /// In en, this message translates to:
  /// **'Delete Java {major}? Instances that need it will not start until it is downloaded again.'**
  String javaDeleteConfirm(int major);

  /// Confirms deleting a downloaded Java runtime.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get javaDeleteConfirmAction;

  /// Button that rescans for installed Java runtimes.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get javaRefresh;

  /// Generic cancel button.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get javaCancel;

  /// Shown after the user cancels a Java runtime download.
  ///
  /// In en, this message translates to:
  /// **'Java download cancelled'**
  String get javaDownloadCancelled;

  /// Shown when installing a Java runtime failed. {reason} is the error message.
  ///
  /// In en, this message translates to:
  /// **'Java could not be downloaded: {reason}'**
  String javaDownloadFailed(String reason);

  /// Shown when a suitable Java is already installed, so no download is offered. {major} is the Java major version.
  ///
  /// In en, this message translates to:
  /// **'Java {major} found on this computer'**
  String javaUseExisting(int major);

  /// Shown when Mojang publishes no runtime that can run this version on this computer. {major} is the Java major version.
  ///
  /// In en, this message translates to:
  /// **'Java {major} is not available for this platform.'**
  String javaUnavailableOnPlatform(int major);

  /// Explains a platform gap, e.g. Java 8 on Apple Silicon. {major} is the Java major version; {platform} is an OS name.
  ///
  /// In en, this message translates to:
  /// **'No Java {major} build is published for {platform}. You can install one yourself and point the instance at it.'**
  String javaUnavailableDetail(int major, String platform);
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
