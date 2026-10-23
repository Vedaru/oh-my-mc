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

  /// Session state chip on the launch page while a game is up.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get launchRunning;

  /// Session state chip while the launcher is preparing a launch.
  ///
  /// In en, this message translates to:
  /// **'Starting'**
  String get launchStarting;

  /// Placeholder when the instance list is empty.
  ///
  /// In en, this message translates to:
  /// **'No instance selected'**
  String get noInstanceSelected;

  /// Shown on the launch screen while no instance is selected, under the title.
  ///
  /// In en, this message translates to:
  /// **'Create one on the Instances page, then launch it from here.'**
  String get launchEmptyHint;

  /// Title of the dialog the version card opens.
  ///
  /// In en, this message translates to:
  /// **'Versions'**
  String get launchVersionListTitle;

  /// Shown in the version list when nothing is installed.
  ///
  /// In en, this message translates to:
  /// **'No versions installed yet. Create one from the download page.'**
  String get launchVersionListEmpty;

  /// Tooltip of the per-row action that opens that version's settings.
  ///
  /// In en, this message translates to:
  /// **'Version settings'**
  String get launchVersionSettings;

  /// Dialog action that opens the instance management screen.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get launchManageInstances;

  /// Dialog action that creates an instance.
  ///
  /// In en, this message translates to:
  /// **'New instance'**
  String get launchNewInstance;

  /// Creates a new instance.
  ///
  /// In en, this message translates to:
  /// **'New instance'**
  String get instanceCreate;

  /// Label for the read-only version row.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get instanceVersionLabel;

  /// Dialog title shown when creating an instance but no version is installed.
  ///
  /// In en, this message translates to:
  /// **'No game version is installed yet'**
  String get instanceNoVersions;

  /// Explains that a version must be installed first, with the download page as the action.
  ///
  /// In en, this message translates to:
  /// **'An instance has to point at an installed version. Install one on the Download page first.'**
  String get instanceNoVersionsHint;

  /// Duplicates an instance.
  ///
  /// In en, this message translates to:
  /// **'Clone'**
  String get instanceClone;

  /// Snackbar when cloning an instance fails.
  ///
  /// In en, this message translates to:
  /// **'Clone failed: {error}'**
  String instanceCloneFailed(String error);

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

  /// Confirmation before deleting an instance along with the folder that holds its own files.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}? Its folder and everything in it will be removed. This cannot be undone.'**
  String instanceDeleteConfirmFiles(String name);

  /// Shown when an instance's folder could not be deleted after the instance itself was removed, usually because a file is held open.
  ///
  /// In en, this message translates to:
  /// **'The instance was removed from the list, but its folder could not be deleted. Remove it by hand: {path}'**
  String instanceDeleteFilesFailed(String path);

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

  /// Loader choice meaning "no loader": the plain game version.
  ///
  /// In en, this message translates to:
  /// **'Vanilla'**
  String get loaderVanilla;

  /// Marks a version that is already installed.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get downloadInstalled;

  /// Trailing state of a version whose install was interrupted.
  ///
  /// In en, this message translates to:
  /// **'Incomplete'**
  String get downloadIncomplete;

  /// Copies the whole install log to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy install log'**
  String get installLogCopy;

  /// Confirmation after copying the install log.
  ///
  /// In en, this message translates to:
  /// **'Install log copied'**
  String get installLogCopied;

  /// Heading of the repair offer on the launch page.
  ///
  /// In en, this message translates to:
  /// **'The install did not finish'**
  String get launchRepairTitle;

  /// Heading when the version directory was deleted.
  ///
  /// In en, this message translates to:
  /// **'This version is not installed'**
  String get launchRepairMissingTitle;

  /// Body when the version is gone; version is the version id.
  ///
  /// In en, this message translates to:
  /// **'{version} is not on disk any more. Install it again to launch this instance.'**
  String launchRepairMissingBody(String version);

  /// Body of the repair offer; count is the missing file count.
  ///
  /// In en, this message translates to:
  /// **'{count} file(s) are missing, so this version cannot start. Resuming only downloads what is absent.'**
  String launchRepairBody(int count);

  /// Button that resumes an interrupted install.
  ///
  /// In en, this message translates to:
  /// **'Resume install'**
  String get launchRepairAction;

  /// Button that opens the download page for a version that is not on disk.
  ///
  /// In en, this message translates to:
  /// **'Install it'**
  String get launchMissingVersionAction;

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

  /// Setup section: theme, motion and language.
  ///
  /// In en, this message translates to:
  /// **'Interface'**
  String get setupUi;

  /// Settings row label: the accent colour the whole theme is seeded from.
  ///
  /// In en, this message translates to:
  /// **'Accent colour'**
  String get setupAccent;

  /// Settings row hint under the accent label.
  ///
  /// In en, this message translates to:
  /// **'Seeds every colour in the app. Both themes follow it.'**
  String get setupAccentHint;

  /// Name of the blue accent swatch, used as its tooltip and screen-reader label.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get accentBlue;

  /// Name of the teal accent swatch.
  ///
  /// In en, this message translates to:
  /// **'Teal'**
  String get accentTeal;

  /// Name of the green accent swatch.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get accentGreen;

  /// Name of the orange accent swatch.
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get accentOrange;

  /// Name of the red accent swatch.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get accentRed;

  /// Name of the purple accent swatch.
  ///
  /// In en, this message translates to:
  /// **'Purple'**
  String get accentPurple;

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

  /// Light/dark/system theme choice.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get setupThemeMode;

  /// Hint under the theme choice.
  ///
  /// In en, this message translates to:
  /// **'Follow system changes with the OS.'**
  String get setupThemeHint;

  /// Explains the zh_Hant fallback in the language chooser.
  ///
  /// In en, this message translates to:
  /// **'Simplified Chinese and Traditional Chinese both use the Chinese translations.'**
  String get setupLanguageHint;

  /// Language choice: English.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// Language choice: Chinese (either script).
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get languageChinese;

  /// Label for the offline player name field.
  ///
  /// In en, this message translates to:
  /// **'Player name'**
  String get setupPlayerName;

  /// The validation rule for the player name.
  ///
  /// In en, this message translates to:
  /// **'3-16 letters, digits or underscores.'**
  String get setupPlayerNameHint;

  /// Explains what the global heap slider affects.
  ///
  /// In en, this message translates to:
  /// **'Used by instances that do not set their own.'**
  String get setupMemoryHint;

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

  /// Second line of the empty log console on the launch page.
  ///
  /// In en, this message translates to:
  /// **'Start the game and its output shows up here.'**
  String get launchLogEmptyHint;

  /// Placeholder in the log search box.
  ///
  /// In en, this message translates to:
  /// **'Search the log'**
  String get logsSearchHint;

  /// Toggle that hides ordinary log lines and keeps failures.
  ///
  /// In en, this message translates to:
  /// **'Errors only'**
  String get logsOnlyErrors;

  /// Entry in the log list for the running session.
  ///
  /// In en, this message translates to:
  /// **'Current session'**
  String get logsSessionCurrent;

  /// Supporting text of the live session entry.
  ///
  /// In en, this message translates to:
  /// **'{count} lines'**
  String logsLineCount(int count);

  /// Heading over the logs written by earlier launches.
  ///
  /// In en, this message translates to:
  /// **'Saved sessions'**
  String get logsSessionHistory;

  /// Shown when no log file exists on disk.
  ///
  /// In en, this message translates to:
  /// **'No saved sessions yet.'**
  String get logsSessionEmpty;

  /// Shown when the log has lines but the search or filter hides them all.
  ///
  /// In en, this message translates to:
  /// **'No lines match the filter.'**
  String get logsNoMatches;

  /// Copies the whole log to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get logsCopy;

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

  /// Context menu item that opens the instance detail page.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get instanceOpen;

  /// Shown when a detail link points at a deleted instance.
  ///
  /// In en, this message translates to:
  /// **'This instance no longer exists.'**
  String get instanceMissing;

  /// Returns to the previous screen.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get actionBack;

  /// Detail page section: name, version, folder mode.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get instanceSectionGeneral;

  /// Detail page section: heap size and JVM choice.
  ///
  /// In en, this message translates to:
  /// **'Java and memory'**
  String get instanceSectionRuntime;

  /// Section heading for the per-instance game window size.
  ///
  /// In en, this message translates to:
  /// **'Window'**
  String get instanceSectionWindow;

  /// Label of the window width field, in pixels.
  ///
  /// In en, this message translates to:
  /// **'Width'**
  String get instanceWindowWidth;

  /// Label of the window height field, in pixels.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get instanceWindowHeight;

  /// Hint under the window size fields.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to use the game\'s own window size.'**
  String get instanceWindowHint;

  /// Label of the fullscreen switch.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen'**
  String get instanceFullscreen;

  /// Tooltip of the trailing action that opens a folder.
  ///
  /// In en, this message translates to:
  /// **'Open folder'**
  String get instanceOpenFolderTooltip;

  /// Detail page section: extra JVM and game arguments.
  ///
  /// In en, this message translates to:
  /// **'Arguments'**
  String get instanceSectionArguments;

  /// Label for the extra JVM argument editor.
  ///
  /// In en, this message translates to:
  /// **'JVM arguments'**
  String get instanceJvmArgsLabel;

  /// Explains the JVM argument editor.
  ///
  /// In en, this message translates to:
  /// **'One per line. Passed to Java before the game starts, e.g. -XX:+UseG1GC'**
  String get instanceJvmArgsHint;

  /// Label for the extra game argument editor.
  ///
  /// In en, this message translates to:
  /// **'Game arguments'**
  String get instanceGameArgsLabel;

  /// Explains the game argument editor.
  ///
  /// In en, this message translates to:
  /// **'One per line. Passed to the game, e.g. --fullscreen'**
  String get instanceGameArgsHint;

  /// How many arguments the current text parses to, so a quoting mistake is visible before launch.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No extra arguments} =1{1 argument} other{{count} arguments}}'**
  String instanceArgsPreview(int count);

  /// The arguments as the launcher will pass them, one per entry, after parsing quotes.
  ///
  /// In en, this message translates to:
  /// **'Will pass: {args}'**
  String instanceArgsPreviewList(String args);

  /// Label for the instance name field.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get instanceNameLabel;

  /// Label for the isolation switch.
  ///
  /// In en, this message translates to:
  /// **'Separate game folder'**
  String get instanceIsolationLabel;

  /// Warns that toggling isolation leaves files where they are.
  ///
  /// In en, this message translates to:
  /// **'Existing files are not moved when this changes.'**
  String get instanceIsolationHint;

  /// Warning shown when an instance is set to isolated: it starts with an empty game directory rather than migrating existing files.
  ///
  /// In en, this message translates to:
  /// **'This instance gets an empty folder of its own. Worlds, mods and options already in the shared folder stay there and are not copied or moved.'**
  String get instanceIsolationEmpty;

  /// Isolation switch, on: this instance has its own files.
  ///
  /// In en, this message translates to:
  /// **'Separate folder'**
  String get instanceIsolationOn;

  /// Isolation switch, off: files are shared with other instances.
  ///
  /// In en, this message translates to:
  /// **'Shared folder'**
  String get instanceIsolationOff;

  /// Label for the per-instance heap setting.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get instanceMemoryLabel;

  /// Explains the unset state of the memory override.
  ///
  /// In en, this message translates to:
  /// **'Off means the global default.'**
  String get instanceMemoryHint;

  /// Memory override off; the global value is shown.
  ///
  /// In en, this message translates to:
  /// **'Using the default ({mb} MB)'**
  String instanceMemoryUsingDefault(int mb);

  /// A heap size in megabytes.
  ///
  /// In en, this message translates to:
  /// **'{mb} MB'**
  String instanceMemoryMb(int mb);

  /// Shown under the heap slider to discourage maxing it out.
  ///
  /// In en, this message translates to:
  /// **'More memory is not always faster: garbage collection takes longer on a large heap.'**
  String get instanceMemoryBigger;

  /// Label for the per-instance JVM choice.
  ///
  /// In en, this message translates to:
  /// **'Java'**
  String get instanceJavaLabel;

  /// Explains the Java picker.
  ///
  /// In en, this message translates to:
  /// **'Which JVM runs this instance.'**
  String get instanceJavaHint;

  /// Default Java choice: the version decides.
  ///
  /// In en, this message translates to:
  /// **'Automatic (picked by version)'**
  String get instanceJavaAutomatic;

  /// Button that runs the selected JVM to check it works.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get instanceJavaTest;

  /// Shown while the selected JVM is being run.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get instanceJavaTestRunning;

  /// Result of a successful JVM probe.
  ///
  /// In en, this message translates to:
  /// **'Works: Java {major}, {version}, {vendor}'**
  String instanceJavaTestOk(int major, String version, String vendor);

  /// Fills the vendor slot when the JVM does not report one.
  ///
  /// In en, this message translates to:
  /// **'an unnamed vendor'**
  String get instanceJavaTestNoVendor;

  /// Explains what the Java test button does before it is pressed.
  ///
  /// In en, this message translates to:
  /// **'Runs this file to confirm it starts and reports its version.'**
  String get instanceJavaTestHint;

  /// Result of a JVM probe that produced no version, which means the file is missing, is not a JVM, or cannot run on this machine.
  ///
  /// In en, this message translates to:
  /// **'This file did not answer as a Java runtime. Pick another one, or download it again.'**
  String get instanceJavaTestFailed;

  /// Java picker hint when the launcher has no managed runtime.
  ///
  /// In en, this message translates to:
  /// **'No downloaded runtimes yet. Get one from Setup.'**
  String get instanceJavaNoneDownloaded;

  /// Java picker hint when runtimes are available.
  ///
  /// In en, this message translates to:
  /// **'Only runtimes this launcher downloaded are listed here.'**
  String get instanceJavaHintDetail;

  /// Label for the playtime row.
  ///
  /// In en, this message translates to:
  /// **'Playtime'**
  String get instancePlaytimeLabel;

  /// Total playtime and the last session's date.
  ///
  /// In en, this message translates to:
  /// **'{duration} in total, last played {date}'**
  String instancePlaytimeValue(String duration, String date);

  /// Shown when no file manager could be launched.
  ///
  /// In en, this message translates to:
  /// **'Could not open the folder.'**
  String get instanceOpenFolderFailed;

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

  /// How much of the current download is done, as a whole percentage. Sits next to the byte counter.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String downloadPercent(int percent);

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

  /// Heading over the user-supplied Java search directories.
  ///
  /// In en, this message translates to:
  /// **'Java directories'**
  String get javaDirsTitle;

  /// Explains that a bundled runtime is installed automatically and extra directories can be added.
  ///
  /// In en, this message translates to:
  /// **'The launcher installs its own Java when a version needs one. Add a folder here to reuse JDKs you already have.'**
  String get javaDirsHint;

  /// Button that opens a directory picker for an extra Java search folder.
  ///
  /// In en, this message translates to:
  /// **'Add folder…'**
  String get javaAddDir;

  /// Removes one user-supplied Java directory from the search list.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get javaRemoveDir;

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

  /// Button that imports a modpack file.
  ///
  /// In en, this message translates to:
  /// **'Import pack'**
  String get packImport;

  /// State of the import button while files land.
  ///
  /// In en, this message translates to:
  /// **'Importing…'**
  String get packImporting;

  /// Snackbar after a pack import.
  ///
  /// In en, this message translates to:
  /// **'Imported \"{name}\" · {count} files'**
  String packImported(String name, int count);

  /// Snackbar when a pack import fails.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String packImportFailed(String error);

  /// Button that writes the instance as a .zip pack.
  ///
  /// In en, this message translates to:
  /// **'Export pack'**
  String get packExport;

  /// Snackbar after exporting a pack.
  ///
  /// In en, this message translates to:
  /// **'Exported {count} files to {path}'**
  String packExported(int count, String path);

  /// Snackbar when an export fails.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String packExportFailed(String error);

  /// Crash action: open where memory is set.
  ///
  /// In en, this message translates to:
  /// **'Version settings'**
  String get diagnosisOpenSettings;

  /// Crash action: open the Java settings.
  ///
  /// In en, this message translates to:
  /// **'Choose Java'**
  String get diagnosisChooseJava;

  /// Crash action: get a runtime the launcher manages.
  ///
  /// In en, this message translates to:
  /// **'Install Java'**
  String get diagnosisInstallJava;

  /// Crash action: open the mod list.
  ///
  /// In en, this message translates to:
  /// **'Mods'**
  String get diagnosisOpenMods;

  /// Crash action: open the log page.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get diagnosisOpenLogs;

  /// Crash action: open the download page to repair.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get diagnosisOpenDownload;

  /// Crash action: launch once more.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get diagnosisRetry;

  /// Settings section for diagnostics and LAN.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get settingsNetworkTitle;

  /// Explanation above the network diagnostics in settings.
  ///
  /// In en, this message translates to:
  /// **'Measures the CDNs the launcher downloads from, and shows the address to share for LAN play.'**
  String get settingsNetworkHint;

  /// Button that measures mirror throughput.
  ///
  /// In en, this message translates to:
  /// **'Test download speed'**
  String get settingsSpeedTest;

  /// State while the speed test runs.
  ///
  /// In en, this message translates to:
  /// **'Testing…'**
  String get settingsSpeedTesting;

  /// Label for the local IP shown for LAN play.
  ///
  /// In en, this message translates to:
  /// **'LAN address'**
  String get settingsLanAddress;

  /// Shown when no LAN address exists.
  ///
  /// In en, this message translates to:
  /// **'No network interface found'**
  String get settingsLanUnknown;

  /// Copy the LAN address to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get settingsCopy;

  /// Confirmation after copying.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get settingsCopied;

  /// Crash diagnosis title (outOfMemory).
  ///
  /// In en, this message translates to:
  /// **'Out of memory'**
  String get diagOutOfMemoryTitle;

  /// Crash diagnosis explanation (outOfMemory).
  ///
  /// In en, this message translates to:
  /// **'The game ran out of heap. A modded 1.20 instance usually needs 4 GB or more; raise the memory in the version settings unless the machine has no more to give. On 32-bit Java it needs a 64-bit runtime instead.'**
  String get diagOutOfMemoryBody;

  /// Crash diagnosis title (outOfMetaspace).
  ///
  /// In en, this message translates to:
  /// **'Out of metaspace'**
  String get diagOutOfMetaspaceTitle;

  /// Crash diagnosis explanation (outOfMetaspace).
  ///
  /// In en, this message translates to:
  /// **'Not the game heap: the JVM ran out of class metadata. Raising the memory slider does not help - this is an old Java with a huge modpack, so switch to a Java 17 or 21 runtime.'**
  String get diagOutOfMetaspaceBody;

  /// Crash diagnosis title (javaTooOld).
  ///
  /// In en, this message translates to:
  /// **'This Java is too old'**
  String get diagJavaTooOldTitle;

  /// Crash diagnosis explanation (javaTooOld).
  ///
  /// In en, this message translates to:
  /// **'A class in the game or a mod was compiled for a newer Java than the one selected. Choose a newer runtime in the version settings, or let the launcher install one.'**
  String get diagJavaTooOldBody;

  /// Crash diagnosis title (javaTooOldNamed).
  ///
  /// In en, this message translates to:
  /// **'This version needs Java {java}'**
  String diagJavaTooOldNamedTitle(int java);

  /// Crash diagnosis explanation (javaTooOldNamed).
  ///
  /// In en, this message translates to:
  /// **'The selected Java is older than Java {java}, which the game or a mod requires. Pick a Java {java} runtime in the version settings, or let the launcher install one.'**
  String diagJavaTooOldNamedBody(int java);

  /// Crash diagnosis title (javaMissing).
  ///
  /// In en, this message translates to:
  /// **'The Java runtime is missing'**
  String get diagJavaMissingTitle;

  /// Crash diagnosis explanation (javaMissing).
  ///
  /// In en, this message translates to:
  /// **'The configured Java is no longer at that path - it was moved, or a launcher-managed runtime was deleted. Pick another one, or install one.'**
  String get diagJavaMissingBody;

  /// Crash diagnosis title (modConflict).
  ///
  /// In en, this message translates to:
  /// **'The mods do not fit together'**
  String get diagModConflictTitle;

  /// Crash diagnosis explanation (modConflict).
  ///
  /// In en, this message translates to:
  /// **'The loader refused the mod set: two mods provide the same thing, or one needs a version of another that is not installed. The log names the mods involved.'**
  String get diagModConflictBody;

  /// Crash diagnosis title (modMismatch).
  ///
  /// In en, this message translates to:
  /// **'A mod does not match the game version'**
  String get diagModMismatchTitle;

  /// Crash diagnosis explanation (modMismatch).
  ///
  /// In en, this message translates to:
  /// **'A class the mod expected is not there. On a modded instance this is a mod built for another Minecraft version; on a vanilla one the installed files are incomplete.'**
  String get diagModMismatchBody;

  /// Crash diagnosis title (missingDependency).
  ///
  /// In en, this message translates to:
  /// **'A mod is missing a dependency'**
  String get diagMissingDependencyTitle;

  /// Crash diagnosis explanation (missingDependency).
  ///
  /// In en, this message translates to:
  /// **'A mod needs another mod that is not installed. Install the missing one - the search dialog pulls dependencies in automatically.'**
  String get diagMissingDependencyBody;

  /// Crash diagnosis title (mixinFailed).
  ///
  /// In en, this message translates to:
  /// **'A mod failed to patch the game'**
  String get diagMixinFailedTitle;

  /// Crash diagnosis explanation (mixinFailed).
  ///
  /// In en, this message translates to:
  /// **'A mixin did not apply, which almost always means the mod was built for a different game or loader version. Remove or update that mod.'**
  String get diagMixinFailedBody;

  /// Crash diagnosis title (mixinFailedNamed).
  ///
  /// In en, this message translates to:
  /// **'A mod failed to patch the game: {mod}'**
  String diagMixinFailedNamedTitle(String mod);

  /// Crash diagnosis explanation (mixinFailedNamed).
  ///
  /// In en, this message translates to:
  /// **'A mixin from {mod} did not apply, which almost always means it was built for a different game or loader version. Remove or update that mod.'**
  String diagMixinFailedNamedBody(String mod);

  /// Crash diagnosis title (archMismatch).
  ///
  /// In en, this message translates to:
  /// **'The native libraries do not match the system'**
  String get diagArchMismatchTitle;

  /// Crash diagnosis explanation (archMismatch).
  ///
  /// In en, this message translates to:
  /// **'LWJGL could not load its native code, which usually means a 32-bit Java on a 64-bit system (or the reverse), or natives extracted by another launcher. Reinstall the version and make sure the Java is 64-bit.'**
  String get diagArchMismatchBody;

  /// Crash diagnosis title (graphicsDriver).
  ///
  /// In en, this message translates to:
  /// **'The graphics driver crashed'**
  String get diagGraphicsDriverTitle;

  /// Crash diagnosis explanation (graphicsDriver).
  ///
  /// In en, this message translates to:
  /// **'Minecraft could not create or use an OpenGL context. Update the GPU driver, and on a laptop make sure the game is not running on a GPU that cannot do OpenGL 3.2.'**
  String get diagGraphicsDriverBody;

  /// Crash diagnosis title (networkFailure).
  ///
  /// In en, this message translates to:
  /// **'Something could not be downloaded'**
  String get diagNetworkFailureTitle;

  /// Crash diagnosis explanation (networkFailure).
  ///
  /// In en, this message translates to:
  /// **'A file could not be fetched. Retry; if it keeps failing, the mirror is unreachable from this network.'**
  String get diagNetworkFailureBody;

  /// Crash diagnosis title (corruptInstall).
  ///
  /// In en, this message translates to:
  /// **'An installed file is damaged'**
  String get diagCorruptInstallTitle;

  /// Crash diagnosis explanation (corruptInstall).
  ///
  /// In en, this message translates to:
  /// **'A jar could not be read - usually an interrupted download or a full disk. Repairing the version re-downloads only the files that fail their check.'**
  String get diagCorruptInstallBody;

  /// Crash diagnosis title (unknown exit).
  ///
  /// In en, this message translates to:
  /// **'The game exited with code {code}'**
  String diagUnknownTitle(String code);

  /// Crash diagnosis explanation (unknown).
  ///
  /// In en, this message translates to:
  /// **'None of the known failure patterns matched. The tail of the log is the place to look: the last exception before the exit is usually the cause.'**
  String get diagUnknownBody;

  /// Section name for the world list.
  ///
  /// In en, this message translates to:
  /// **'Worlds'**
  String get contentSaves;

  /// Title of the server list.
  ///
  /// In en, this message translates to:
  /// **'Servers'**
  String get contentServers;

  /// Explains that enabled resource packs are written to options.txt.
  ///
  /// In en, this message translates to:
  /// **'Enabled packs are written to options.txt, which the game reads on start.'**
  String get contentResourcePacksHint;

  /// Explains that the active shader is picked in game.
  ///
  /// In en, this message translates to:
  /// **'Installed shader packs; pick the active one in game.'**
  String get contentShaderPacksHint;

  /// Warns that deleting a world is permanent.
  ///
  /// In en, this message translates to:
  /// **'A world cannot be downloaded again: back it up before you delete or change it.'**
  String get contentSavesHint;

  /// Explains that this is the in-game multiplayer list.
  ///
  /// In en, this message translates to:
  /// **'The multiplayer server list this instance shows in game.'**
  String get contentServersHint;

  /// Empty state of the resource pack list.
  ///
  /// In en, this message translates to:
  /// **'No resource packs yet.'**
  String get contentEmptyResourcePacks;

  /// Empty state of the shader pack list.
  ///
  /// In en, this message translates to:
  /// **'No shader packs yet.'**
  String get contentEmptyShaderPacks;

  /// Empty state of the world list.
  ///
  /// In en, this message translates to:
  /// **'No worlds yet.'**
  String get contentEmptySaves;

  /// Empty state of the server list.
  ///
  /// In en, this message translates to:
  /// **'No servers yet.'**
  String get contentEmptyServers;

  /// Confirmation title before deleting a content entry.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String contentDeleteTitle(Object name);

  /// Confirmation body before deleting a content entry.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get contentDeleteBody;

  /// Generic delete action label.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// Radio label: follow the fastest measured source.
  ///
  /// In en, this message translates to:
  /// **'Automatic ({name} first)'**
  String sourceAuto(String name);

  /// Radio label: always use the official CDN.
  ///
  /// In en, this message translates to:
  /// **'Mojang'**
  String get sourceOfficial;

  /// Radio label: always use the BMCLAPI mirror.
  ///
  /// In en, this message translates to:
  /// **'BMCLAPI'**
  String get sourceBmclapi;

  /// Catalogue name for mods.
  ///
  /// In en, this message translates to:
  /// **'Mods'**
  String get catalogMods;

  /// Catalogue name for resource packs.
  ///
  /// In en, this message translates to:
  /// **'Resource packs'**
  String get catalogResourcePacks;

  /// Catalogue name for shaders.
  ///
  /// In en, this message translates to:
  /// **'Shaders'**
  String get catalogShaders;

  /// Catalogue name for data packs.
  ///
  /// In en, this message translates to:
  /// **'Data packs'**
  String get catalogDataPacks;

  /// Hint in the catalogue search field.
  ///
  /// In en, this message translates to:
  /// **'Search Modrinth'**
  String get catalogSearchHint;

  /// Shown when a catalogue search returns nothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches that.'**
  String get catalogEmpty;

  /// Install action on a catalogue result.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get catalogInstall;

  /// Shown when a vanilla instance opens the mod catalogue.
  ///
  /// In en, this message translates to:
  /// **'This version cannot take mods'**
  String get catalogNeedsLoader;

  /// Shown when no world exists or none was chosen.
  ///
  /// In en, this message translates to:
  /// **'A data pack belongs to a world. Create or open a world first.'**
  String get catalogNeedsWorld;

  /// No description provided for @catalogUnknownVersion.
  ///
  /// In en, this message translates to:
  /// **'The game version could not be read from this instance.'**
  String get catalogUnknownVersion;

  /// Title of the world picker for data packs.
  ///
  /// In en, this message translates to:
  /// **'Which world?'**
  String get catalogPickWorld;

  /// States the filters a mod search applies.
  ///
  /// In en, this message translates to:
  /// **'{loader} · {game} — matches only what can load here'**
  String catalogFilteredLoader(String loader, String game);

  /// States the game version filter.
  ///
  /// In en, this message translates to:
  /// **'{game} — matches only what can load here'**
  String catalogFilteredGame(String game);

  /// Shown when no instance is selected.
  ///
  /// In en, this message translates to:
  /// **'Select an instance on the Launch page first: content installs into one.'**
  String get catalogNoTarget;

  /// Button that imports a world archive.
  ///
  /// In en, this message translates to:
  /// **'Import world (.zip)'**
  String get catalogImportWorld;

  /// State of the world import button.
  ///
  /// In en, this message translates to:
  /// **'Importing…'**
  String get catalogImporting;

  /// Snackbar after a world import.
  ///
  /// In en, this message translates to:
  /// **'Imported “{name}”'**
  String catalogWorldImported(String name);

  /// Snackbar when a world import fails.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String catalogWorldImportFailed(String error);

  /// Shows which instance receives the content.
  ///
  /// In en, this message translates to:
  /// **'Installing into “{name}”'**
  String catalogTarget(String name);

  /// Explanation above the LAN play controls.
  ///
  /// In en, this message translates to:
  /// **'Worlds this network has opened to LAN, and opening one so a friend outside can join.'**
  String get lanHint;

  /// Button that listens for the game LAN broadcasts.
  ///
  /// In en, this message translates to:
  /// **'Find LAN worlds'**
  String get lanScan;

  /// State while the LAN scan runs.
  ///
  /// In en, this message translates to:
  /// **'Listening…'**
  String get lanScanning;

  /// Shown after a scan that found nothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing announced a world in the last few seconds.'**
  String get lanNothingFound;

  /// Fallback name for an announcement without a MOTD.
  ///
  /// In en, this message translates to:
  /// **'Unnamed world'**
  String get lanUnnamedWorld;

  /// Button that maps the world port on the router.
  ///
  /// In en, this message translates to:
  /// **'Open port'**
  String get lanOpenPort;

  /// Label of the active port mapping row.
  ///
  /// In en, this message translates to:
  /// **'Open to the internet'**
  String get lanMappingActive;

  /// Button that removes the mapping.
  ///
  /// In en, this message translates to:
  /// **'Close port'**
  String get lanClosePort;

  /// Shown when the gateway cannot report its public IP.
  ///
  /// In en, this message translates to:
  /// **'The router did not report an external address'**
  String get lanNoExternalAddress;

  /// Settings section with the version and update check.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutTitle;

  /// Label of the current version row.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get aboutVersion;

  /// Button that queries the release feed.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get aboutCheck;

  /// State while the update check runs.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get aboutChecking;

  /// Shown when no newer release exists.
  ///
  /// In en, this message translates to:
  /// **'{version} is the newest version.'**
  String aboutUpToDate(String version);

  /// Shown when the check could not answer.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the release feed. Nothing is wrong with this install.'**
  String get aboutCheckFailed;

  /// Shown when a newer release exists.
  ///
  /// In en, this message translates to:
  /// **'{version} is available'**
  String aboutNewVersion(String version);

  /// Release date of the newer version.
  ///
  /// In en, this message translates to:
  /// **'Published {date}'**
  String aboutPublished(String date);

  /// Opens the release installer asset.
  ///
  /// In en, this message translates to:
  /// **'Download installer'**
  String get aboutDownload;

  /// Opens the release page.
  ///
  /// In en, this message translates to:
  /// **'Release notes'**
  String get aboutReleasePage;

  /// Settings section: language.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get setupSectionGeneral;

  /// Settings section: theme and accent.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get setupSectionAppearance;

  /// Tooltip of the overflow menu.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get actionMore;

  /// Primary action on the instance page.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get actionLaunch;

  /// Instance page tab: what this instance is.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get detailTabOverview;

  /// Instance page tab: what it runs with.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get detailTabSettings;

  /// Button in the instance content tab that opens the catalogue.
  ///
  /// In en, this message translates to:
  /// **'Install from Modrinth'**
  String get contentInstall;

  /// Hint above the mod list.
  ///
  /// In en, this message translates to:
  /// **'Mods in this instance. A mod is switched off by renaming its jar.'**
  String get contentModsHint;

  /// Hint above the data pack list.
  ///
  /// In en, this message translates to:
  /// **'Data packs belong to a world: pick one, then install or remove its packs.'**
  String get contentDataPacksHint;

  /// Empty state of the mod list.
  ///
  /// In en, this message translates to:
  /// **'No mods yet.'**
  String get contentEmptyMods;

  /// Empty state of the data pack list.
  ///
  /// In en, this message translates to:
  /// **'No data packs in this world yet.'**
  String get contentEmptyDataPacks;

  /// Adds a server to servers.dat.
  ///
  /// In en, this message translates to:
  /// **'Add server'**
  String get contentAddServer;

  /// Label for the server name field in the add-server dialog.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get contentServerName;

  /// Label for the server address field in the add-server dialog.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get contentServerAddress;

  /// Confirm button that saves the form.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// Second line of the empty mod list.
  ///
  /// In en, this message translates to:
  /// **'Drag a jar into the mods folder, or install one from Modrinth.'**
  String get contentEmptyModsHint;

  /// Second line of any empty content list.
  ///
  /// In en, this message translates to:
  /// **'Use the button above to add one, or open the folder and drop a file in.'**
  String get contentEmptyHint;

  /// Tooltip of the button that zips a world.
  ///
  /// In en, this message translates to:
  /// **'Back up'**
  String get worldBackup;

  /// Snackbar after a world backup, with the file name.
  ///
  /// In en, this message translates to:
  /// **'Backed up to {name}'**
  String worldBackupDone(String name);

  /// Snackbar when a world backup failed.
  ///
  /// In en, this message translates to:
  /// **'Backup failed: {error}'**
  String worldBackupFailed(String error);

  /// Refresh a list that reads live state (server pings).
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get actionRefresh;

  /// Shown where a server's MOTD would be when it did not answer.
  ///
  /// In en, this message translates to:
  /// **'No answer'**
  String get serverOffline;

  /// Language option that follows the OS, naming what the OS currently resolves to.
  ///
  /// In en, this message translates to:
  /// **'Follow system ({language})'**
  String languageSystemWith(String language);

  /// Button that asks Modrinth which installed mods are out of date.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get modsCheckUpdates;

  /// Same button while the check runs.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get modsChecking;

  /// Count of mods with a newer version.
  ///
  /// In en, this message translates to:
  /// **'{count} updates available'**
  String modsUpdatesFound(int count);

  /// The version an update would move the mod to.
  ///
  /// In en, this message translates to:
  /// **'Update to {version}'**
  String modsUpdateTo(String version);

  /// Tooltip of the per-row update button.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get modsUpdateAction;

  /// Label of the setting that picks a wallpaper image.
  ///
  /// In en, this message translates to:
  /// **'Background picture'**
  String get setupBackground;

  /// Explains the wallpaper and its scrim.
  ///
  /// In en, this message translates to:
  /// **'Shown behind every page under a scrim. Leave empty for the plain surface.'**
  String get setupBackgroundHint;

  /// Button that opens a file picker for the wallpaper.
  ///
  /// In en, this message translates to:
  /// **'Choose picture…'**
  String get setupBackgroundPick;

  /// Button that removes the wallpaper.
  ///
  /// In en, this message translates to:
  /// **'Use none'**
  String get setupBackgroundClear;

  /// Reported when the chosen file is not a readable image.
  ///
  /// In en, this message translates to:
  /// **'Could not use that file.'**
  String get setupBackgroundFailed;

  /// Button that restores a world from a backup zip.
  ///
  /// In en, this message translates to:
  /// **'Restore from backup…'**
  String get worldRestore;

  /// Snackbar after a restore, naming the new world folder.
  ///
  /// In en, this message translates to:
  /// **'Restored as {name}'**
  String worldRestoreDone(String name);

  /// Snackbar when a restore failed.
  ///
  /// In en, this message translates to:
  /// **'Restore failed: {error}'**
  String worldRestoreFailed(String error);

  /// Tooltip of the button that removes an installed version.
  ///
  /// In en, this message translates to:
  /// **'Uninstall'**
  String get downloadUninstall;

  /// Confirmation title for uninstalling a version.
  ///
  /// In en, this message translates to:
  /// **'Uninstall {version}?'**
  String downloadUninstallTitle(String version);

  /// Explains exactly what an uninstall deletes and keeps.
  ///
  /// In en, this message translates to:
  /// **'Deletes this version\'s own files. Shared libraries and assets are kept, and instances using it are left alone - they will report a missing version.'**
  String get downloadUninstallBody;

  /// Snackbar after uninstalling a version.
  ///
  /// In en, this message translates to:
  /// **'{version} uninstalled'**
  String downloadUninstallDone(String version);

  /// Settings section for launcher accounts.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get setupAccounts;

  /// Label for an offline account.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get accountOffline;

  /// Label for an authlib-injector style account.
  ///
  /// In en, this message translates to:
  /// **'Third-party'**
  String get accountThirdParty;

  /// Button that adds an offline account.
  ///
  /// In en, this message translates to:
  /// **'Add offline account'**
  String get accountAdd;

  /// The rule for a Minecraft player name.
  ///
  /// In en, this message translates to:
  /// **'3-16 letters, digits or underscore'**
  String get accountNameHint;

  /// Explains that the active account is the identity a world belongs to.
  ///
  /// In en, this message translates to:
  /// **'The account the game starts as. Its uuid is what a world belongs to.'**
  String get accountActiveHint;

  /// Empty state title for the account list.
  ///
  /// In en, this message translates to:
  /// **'No accounts yet'**
  String get accountEmpty;

  /// Empty state body for the account list.
  ///
  /// In en, this message translates to:
  /// **'Add an offline account to pick a name the game will use.'**
  String get accountEmptyHint;

  /// Removes an account.
  ///
  /// In en, this message translates to:
  /// **'Remove account'**
  String get accountRemove;

  /// Confirmation title for removing an account.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String accountRemoveTitle(String name);

  /// Explains that removing an account keeps the data.
  ///
  /// In en, this message translates to:
  /// **'Only the launcher forgets it. Worlds, servers and mods are untouched.'**
  String get accountRemoveBody;
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
