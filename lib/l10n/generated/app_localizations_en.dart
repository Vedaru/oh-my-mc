// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'oh my mc';

  @override
  String get navLaunch => 'Launch';

  @override
  String get navInstances => 'Instances';

  @override
  String get navDownload => 'Download';

  @override
  String get navSetup => 'Setup';

  @override
  String get navLogs => 'Logs';

  @override
  String get navExpand => 'Expand navigation';

  @override
  String get navCollapse => 'Collapse navigation';

  @override
  String get playButton => 'Play';

  @override
  String get stopButton => 'Stop';

  @override
  String get launching => 'Launching…';

  @override
  String get noInstanceSelected => 'No instance selected';

  @override
  String get launchEmptyHint =>
      'Create one on the Instances page, then launch it from here.';

  @override
  String get instanceCreate => 'New instance';

  @override
  String get instanceVersionLabel => 'Version';

  @override
  String get instanceNoVersions => 'No game version is installed yet';

  @override
  String get instanceNoVersionsHint =>
      'An instance has to point at an installed version. Install one on the Download page first.';

  @override
  String get instanceImport => 'Import';

  @override
  String get instanceExport => 'Export';

  @override
  String get instanceClone => 'Clone';

  @override
  String get instanceDelete => 'Delete';

  @override
  String instanceDeleteConfirm(String name) {
    return 'Delete $name? This cannot be undone.';
  }

  @override
  String instanceDeleteConfirmFiles(String name) {
    return 'Delete $name? Its folder and everything in it will be removed. This cannot be undone.';
  }

  @override
  String instanceDeleteFilesFailed(String path) {
    return 'The instance was removed from the list, but its folder could not be deleted. Remove it by hand: $path';
  }

  @override
  String instanceCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count instances',
      one: '1 instance',
      zero: 'No instances',
    );
    return '$_temp0';
  }

  @override
  String get downloadVersions => 'Versions';

  @override
  String get downloadLoaders => 'Loaders';

  @override
  String get loaderVanilla => 'Vanilla';

  @override
  String get downloadInstall => 'Install';

  @override
  String get downloadInstalled => 'Installed';

  @override
  String get downloadRelease => 'Release';

  @override
  String get downloadSnapshot => 'Snapshot';

  @override
  String get downloadOld => 'Old';

  @override
  String get queueTitle => 'Install queue';

  @override
  String get queuePause => 'Pause';

  @override
  String get queueResume => 'Resume';

  @override
  String get queueCancel => 'Cancel';

  @override
  String get setupLaunch => 'Launch';

  @override
  String get setupJava => 'Java';

  @override
  String get setupDownload => 'Download';

  @override
  String get setupUi => 'Interface';

  @override
  String get setupAccent => 'Accent colour';

  @override
  String get setupAccentHint =>
      'Seeds every colour in the app. Both themes follow it.';

  @override
  String get accentBlue => 'Blue';

  @override
  String get accentTeal => 'Teal';

  @override
  String get accentGreen => 'Green';

  @override
  String get accentOrange => 'Orange';

  @override
  String get accentRed => 'Red';

  @override
  String get accentPurple => 'Purple';

  @override
  String get setupMemory => 'Memory';

  @override
  String get setupLanguage => 'Language';

  @override
  String get setupThemeMode => 'Theme';

  @override
  String get setupThemeHint => 'Follow system changes with the OS.';

  @override
  String get setupLanguageHint =>
      'Simplified Chinese and Traditional Chinese both use the Chinese translations.';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => 'Chinese';

  @override
  String get setupPlayerName => 'Player name';

  @override
  String get setupPlayerNameHint => '3-16 letters, digits or underscores.';

  @override
  String get setupMemoryHint => 'Used by instances that do not set their own.';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeSystem => 'Follow system';

  @override
  String get logsTitle => 'Logs';

  @override
  String get logsEmpty => 'No log output yet';

  @override
  String get logsSearchHint => 'Search the log';

  @override
  String get logsOnlyErrors => 'Errors only';

  @override
  String get logsNoMatches => 'No lines match the filter.';

  @override
  String get logsCopy => 'Copy';

  @override
  String get actionRetry => 'Retry';

  @override
  String get actionClose => 'Close';

  @override
  String get errorDownloadFailed => 'Download failed';

  @override
  String get instanceNeverPlayed => 'Never played';

  @override
  String get instanceOpen => 'Open settings';

  @override
  String get instanceMissing => 'This instance no longer exists.';

  @override
  String get actionBack => 'Back';

  @override
  String get instanceSectionGeneral => 'General';

  @override
  String get instanceSectionRuntime => 'Java and memory';

  @override
  String get instanceSectionWindow => 'Window';

  @override
  String get instanceWindowWidth => 'Width';

  @override
  String get instanceWindowHeight => 'Height';

  @override
  String get instanceWindowHint =>
      'Leave empty to use the game\'s own window size.';

  @override
  String get instanceFullscreen => 'Fullscreen';

  @override
  String get instanceFolderMods => 'Mods';

  @override
  String get instanceFolderResourcePacks => 'Resource packs';

  @override
  String get instanceFolderShaderPacks => 'Shaders';

  @override
  String get instanceFolderSaves => 'Saves';

  @override
  String get instanceFolderEmpty => 'Empty';

  @override
  String get instanceSectionFiles => 'Files';

  @override
  String get instanceSectionArguments => 'Arguments';

  @override
  String get instanceJvmArgsLabel => 'JVM arguments';

  @override
  String get instanceJvmArgsHint =>
      'One per line. Passed to Java before the game starts, e.g. -XX:+UseG1GC';

  @override
  String get instanceGameArgsLabel => 'Game arguments';

  @override
  String get instanceGameArgsHint =>
      'One per line. Passed to the game, e.g. --fullscreen';

  @override
  String instanceArgsPreview(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count arguments',
      one: '1 argument',
      zero: 'No extra arguments',
    );
    return '$_temp0';
  }

  @override
  String instanceArgsPreviewList(String args) {
    return 'Will pass: $args';
  }

  @override
  String get instanceNameLabel => 'Name';

  @override
  String get instanceIsolationLabel => 'Separate game folder';

  @override
  String get instanceIsolationHint =>
      'Existing files are not moved when this changes.';

  @override
  String get instanceIsolationEmpty =>
      'This instance gets an empty folder of its own. Worlds, mods and options already in the shared folder stay there and are not copied or moved.';

  @override
  String get instanceIsolationOn => 'Separate folder';

  @override
  String get instanceIsolationOff => 'Shared folder';

  @override
  String get instanceMemoryLabel => 'Memory';

  @override
  String get instanceMemoryHint => 'Off means the global default.';

  @override
  String instanceMemoryUsingDefault(int mb) {
    return 'Using the default ($mb MB)';
  }

  @override
  String instanceMemoryMb(int mb) {
    return '$mb MB';
  }

  @override
  String get instanceMemoryBigger =>
      'More memory is not always faster: garbage collection takes longer on a large heap.';

  @override
  String get instanceJavaLabel => 'Java';

  @override
  String get instanceJavaHint => 'Which JVM runs this instance.';

  @override
  String get instanceJavaAutomatic => 'Automatic (picked by version)';

  @override
  String get instanceJavaTest => 'Test';

  @override
  String get instanceJavaTestRunning => 'Checking…';

  @override
  String instanceJavaTestOk(int major, String version, String vendor) {
    return 'Works: Java $major, $version, $vendor';
  }

  @override
  String get instanceJavaTestNoVendor => 'an unnamed vendor';

  @override
  String get instanceJavaTestHint =>
      'Runs this file to confirm it starts and reports its version.';

  @override
  String get instanceJavaTestFailed =>
      'This file did not answer as a Java runtime. Pick another one, or download it again.';

  @override
  String get instanceJavaNoneDownloaded =>
      'No downloaded runtimes yet. Get one from Setup.';

  @override
  String get instanceJavaHintDetail =>
      'Only runtimes this launcher downloaded are listed here.';

  @override
  String get instancePlaytimeLabel => 'Playtime';

  @override
  String instancePlaytimeValue(String duration, String date) {
    return '$duration in total, last played $date';
  }

  @override
  String get instancePathLabel => 'Game folder';

  @override
  String get instanceOpenFolder => 'Open folder';

  @override
  String get instanceOpenFolderFailed => 'Could not open the folder.';

  @override
  String get instanceNameHint => 'Name this instance';

  @override
  String get instancesEmpty => 'No instances yet';

  @override
  String instancesSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count instances could not be read and were skipped',
      one: '1 instance could not be read and was skipped',
    );
    return '$_temp0';
  }

  @override
  String get actionCancel => 'Cancel';

  @override
  String get launchFailedSpawn =>
      'Could not start Java. Check the Java setting.';

  @override
  String get launchFailedRefused =>
      'Launch refused. See the log for the reason.';

  @override
  String get launchFailedPrepare =>
      'Could not prepare the launch. See the log.';

  @override
  String launchExited(int code, String duration) {
    return 'Exited with code $code after $duration';
  }

  @override
  String get screenNotReady => 'This screen is not built yet';

  @override
  String get downloadSearchHint => 'Search versions';

  @override
  String downloadSearchEmpty(String query) {
    return 'No version matches “$query”';
  }

  @override
  String downloadInstalling(String version) {
    return 'Installing $version';
  }

  @override
  String get downloadPhaseManifest => 'Reading version list';

  @override
  String get downloadPhaseVersionJson => 'Reading version metadata';

  @override
  String get downloadPhaseParents => 'Reading inherited metadata';

  @override
  String get downloadPhaseAssetIndex => 'Reading asset index';

  @override
  String get downloadPhasePlanning => 'Working out what to download';

  @override
  String get downloadPhaseDownload => 'Downloading';

  @override
  String get downloadPhaseNatives => 'Unpacking native libraries';

  @override
  String get downloadPhaseAssets => 'Placing assets';

  @override
  String get downloadPhaseVerify => 'Verifying files';

  @override
  String downloadStepOf(int step, int steps) {
    return 'Step $step of $steps';
  }

  @override
  String downloadBytes(String done, String total) {
    return '$done of $total';
  }

  @override
  String downloadPercent(int percent) {
    return '$percent%';
  }

  @override
  String downloadRate(String rate) {
    return '$rate/s';
  }

  @override
  String downloadComplete(String version) {
    return '$version is ready to play';
  }

  @override
  String downloadCompleteWithProblems(String version, int count) {
    return '$version installed, but $count file(s) need repair';
  }

  @override
  String get downloadCancel => 'Cancel install';

  @override
  String get downloadCancelled => 'Install cancelled';

  @override
  String get downloadSourceOfficial => 'Official';

  @override
  String get downloadSourceBmclapi => 'BMCLAPI mirror';

  @override
  String get downloadShowSnapshots => 'Show snapshots';

  @override
  String get downloadStaleCache =>
      'Offline — this version list may be out of date';

  @override
  String get downloadRetry => 'Reload';

  @override
  String javaDownloadTitle(int major) {
    return 'Java $major is required';
  }

  @override
  String javaDownloadWhy(int major) {
    return 'This version needs Java $major, and it was not found on this computer.';
  }

  @override
  String javaDownloadAction(int major) {
    return 'Download and install';
  }

  @override
  String javaDownloadProgress(String done, String total) {
    return '$done / $total';
  }

  @override
  String get javaDownloadExtracting => 'Unpacking…';

  @override
  String javaDownloadDone(int major) {
    return 'Java $major is ready';
  }

  @override
  String get javaUnavailableVersionMissing =>
      'Install this version first; the launcher needs its version file to know which Java it asks for.';

  @override
  String get javaUnavailableNoCatalog =>
      'Could not reach the Java runtime catalogue. Check the connection, then try again.';

  @override
  String javaUnavailableNoBuild(int major, String platform) {
    return 'No Java $major build is published for this system ($platform). Install one manually.';
  }

  @override
  String get javaManagedTitle => 'Downloaded Java runtimes';

  @override
  String get javaManagedEmpty => 'No Java runtimes downloaded yet.';

  @override
  String javaManagedItem(int major, String version) {
    return 'Java $major ($version)';
  }

  @override
  String javaManagedDiskUse(String size) {
    return '$size on disk';
  }

  @override
  String get javaDelete => 'Delete';

  @override
  String javaDeleteConfirm(int major) {
    return 'Delete Java $major? Instances that need it will not start until it is downloaded again.';
  }

  @override
  String get javaDeleteConfirmAction => 'Delete';

  @override
  String get javaRefresh => 'Refresh';

  @override
  String get javaDirsTitle => 'Java directories';

  @override
  String get javaDirsHint =>
      'The launcher installs its own Java when a version needs one. Add a folder here to reuse JDKs you already have.';

  @override
  String get javaAddDir => 'Add folder…';

  @override
  String get javaRemoveDir => 'Remove';

  @override
  String get javaCancel => 'Cancel';

  @override
  String get javaDownloadCancelled => 'Java download cancelled';

  @override
  String javaDownloadFailed(String reason) {
    return 'Java could not be downloaded: $reason';
  }

  @override
  String javaUseExisting(int major) {
    return 'Java $major found on this computer';
  }

  @override
  String javaUnavailableOnPlatform(int major) {
    return 'Java $major is not available for this platform.';
  }

  @override
  String javaUnavailableDetail(int major, String platform) {
    return 'No Java $major build is published for $platform. You can install one yourself and point the instance at it.';
  }
}
