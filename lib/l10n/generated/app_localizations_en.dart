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
  String get playButton => 'Play';

  @override
  String get stopButton => 'Stop';

  @override
  String get launching => 'Launching…';

  @override
  String get launchRunning => 'Running';

  @override
  String get launchStarting => 'Starting';

  @override
  String get noInstanceSelected => 'No instance selected';

  @override
  String get launchEmptyHint =>
      'Create one on the Instances page, then launch it from here.';

  @override
  String get launchVersionListTitle => 'Versions';

  @override
  String get launchVersionListEmpty =>
      'No versions installed yet. Create one from the download page.';

  @override
  String get launchVersionSettings => 'Version settings';

  @override
  String get launchManageInstances => 'Manage';

  @override
  String get launchNewInstance => 'New instance';

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
  String get instanceClone => 'Clone';

  @override
  String instanceCloneFailed(String error) {
    return 'Clone failed: $error';
  }

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
  String get loaderVanilla => 'Vanilla';

  @override
  String get downloadInstalled => 'Installed';

  @override
  String get downloadIncomplete => 'Incomplete';

  @override
  String get installLogCopy => 'Copy install log';

  @override
  String get installLogCopied => 'Install log copied';

  @override
  String get launchRepairTitle => 'The install did not finish';

  @override
  String get launchRepairMissingTitle => 'This version is not installed';

  @override
  String launchRepairMissingBody(String version) {
    return '$version is not on disk any more. Install it again to launch this instance.';
  }

  @override
  String launchRepairBody(int count) {
    return '$count file(s) are missing, so this version cannot start. Resuming only downloads what is absent.';
  }

  @override
  String get launchRepairAction => 'Resume install';

  @override
  String get launchMissingVersionAction => 'Install it';

  @override
  String get downloadRelease => 'Release';

  @override
  String get downloadSnapshot => 'Snapshot';

  @override
  String get setupLaunch => 'Launch';

  @override
  String get setupJava => 'Java';

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
  String get launchLogEmptyHint =>
      'Start the game and its output shows up here.';

  @override
  String get logsSearchHint => 'Search the log';

  @override
  String get logsOnlyErrors => 'Errors only';

  @override
  String get logsSessionCurrent => 'Current session';

  @override
  String logsLineCount(int count) {
    return '$count lines';
  }

  @override
  String get logsSessionHistory => 'Saved sessions';

  @override
  String get logsSessionEmpty => 'No saved sessions yet.';

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
  String get instanceOpenFolderTooltip => 'Open folder';

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
  String get packImport => 'Import pack';

  @override
  String get packImporting => 'Importing…';

  @override
  String packImported(String name, int count) {
    return 'Imported \"$name\" · $count files';
  }

  @override
  String packImportFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String get packExport => 'Export pack';

  @override
  String packExported(int count, String path) {
    return 'Exported $count files to $path';
  }

  @override
  String packExportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get diagnosisOpenSettings => 'Version settings';

  @override
  String get diagnosisChooseJava => 'Choose Java';

  @override
  String get diagnosisInstallJava => 'Install Java';

  @override
  String get diagnosisOpenMods => 'Mods';

  @override
  String get diagnosisOpenLogs => 'Logs';

  @override
  String get diagnosisOpenDownload => 'Download';

  @override
  String get diagnosisRetry => 'Try again';

  @override
  String get settingsNetworkTitle => 'Network';

  @override
  String get settingsNetworkHint =>
      'Measures the CDNs the launcher downloads from, and shows the address to share for LAN play.';

  @override
  String get settingsSpeedTest => 'Test download speed';

  @override
  String get settingsSpeedTesting => 'Testing…';

  @override
  String get settingsLanAddress => 'LAN address';

  @override
  String get settingsLanUnknown => 'No network interface found';

  @override
  String get settingsCopy => 'Copy';

  @override
  String get settingsCopied => 'Copied';

  @override
  String get diagOutOfMemoryTitle => 'Out of memory';

  @override
  String get diagOutOfMemoryBody =>
      'The game ran out of heap. A modded 1.20 instance usually needs 4 GB or more; raise the memory in the version settings unless the machine has no more to give. On 32-bit Java it needs a 64-bit runtime instead.';

  @override
  String get diagOutOfMetaspaceTitle => 'Out of metaspace';

  @override
  String get diagOutOfMetaspaceBody =>
      'Not the game heap: the JVM ran out of class metadata. Raising the memory slider does not help - this is an old Java with a huge modpack, so switch to a Java 17 or 21 runtime.';

  @override
  String get diagJavaTooOldTitle => 'This Java is too old';

  @override
  String get diagJavaTooOldBody =>
      'A class in the game or a mod was compiled for a newer Java than the one selected. Choose a newer runtime in the version settings, or let the launcher install one.';

  @override
  String diagJavaTooOldNamedTitle(int java) {
    return 'This version needs Java $java';
  }

  @override
  String diagJavaTooOldNamedBody(int java) {
    return 'The selected Java is older than Java $java, which the game or a mod requires. Pick a Java $java runtime in the version settings, or let the launcher install one.';
  }

  @override
  String get diagJavaMissingTitle => 'The Java runtime is missing';

  @override
  String get diagJavaMissingBody =>
      'The configured Java is no longer at that path - it was moved, or a launcher-managed runtime was deleted. Pick another one, or install one.';

  @override
  String get diagModConflictTitle => 'The mods do not fit together';

  @override
  String get diagModConflictBody =>
      'The loader refused the mod set: two mods provide the same thing, or one needs a version of another that is not installed. The log names the mods involved.';

  @override
  String get diagModMismatchTitle => 'A mod does not match the game version';

  @override
  String get diagModMismatchBody =>
      'A class the mod expected is not there. On a modded instance this is a mod built for another Minecraft version; on a vanilla one the installed files are incomplete.';

  @override
  String get diagMissingDependencyTitle => 'A mod is missing a dependency';

  @override
  String get diagMissingDependencyBody =>
      'A mod needs another mod that is not installed. Install the missing one - the search dialog pulls dependencies in automatically.';

  @override
  String get diagMixinFailedTitle => 'A mod failed to patch the game';

  @override
  String get diagMixinFailedBody =>
      'A mixin did not apply, which almost always means the mod was built for a different game or loader version. Remove or update that mod.';

  @override
  String diagMixinFailedNamedTitle(String mod) {
    return 'A mod failed to patch the game: $mod';
  }

  @override
  String diagMixinFailedNamedBody(String mod) {
    return 'A mixin from $mod did not apply, which almost always means it was built for a different game or loader version. Remove or update that mod.';
  }

  @override
  String get diagArchMismatchTitle =>
      'The native libraries do not match the system';

  @override
  String get diagArchMismatchBody =>
      'LWJGL could not load its native code, which usually means a 32-bit Java on a 64-bit system (or the reverse), or natives extracted by another launcher. Reinstall the version and make sure the Java is 64-bit.';

  @override
  String get diagGraphicsDriverTitle => 'The graphics driver crashed';

  @override
  String get diagGraphicsDriverBody =>
      'Minecraft could not create or use an OpenGL context. Update the GPU driver, and on a laptop make sure the game is not running on a GPU that cannot do OpenGL 3.2.';

  @override
  String get diagNetworkFailureTitle => 'Something could not be downloaded';

  @override
  String get diagNetworkFailureBody =>
      'A file could not be fetched. Retry; if it keeps failing, the mirror is unreachable from this network.';

  @override
  String get diagCorruptInstallTitle => 'An installed file is damaged';

  @override
  String get diagCorruptInstallBody =>
      'A jar could not be read - usually an interrupted download or a full disk. Repairing the version re-downloads only the files that fail their check.';

  @override
  String diagUnknownTitle(String code) {
    return 'The game exited with code $code';
  }

  @override
  String get diagUnknownBody =>
      'None of the known failure patterns matched. The tail of the log is the place to look: the last exception before the exit is usually the cause.';

  @override
  String get contentSaves => 'Worlds';

  @override
  String get contentServers => 'Servers';

  @override
  String get contentResourcePacksHint =>
      'Enabled packs are written to options.txt, which the game reads on start.';

  @override
  String get contentShaderPacksHint =>
      'Installed shader packs; pick the active one in game.';

  @override
  String get contentSavesHint =>
      'Worlds in this instance. Deleting one is permanent.';

  @override
  String get contentServersHint =>
      'The multiplayer server list this instance shows in game.';

  @override
  String get contentEmptyResourcePacks => 'No resource packs yet.';

  @override
  String get contentEmptyShaderPacks => 'No shader packs yet.';

  @override
  String get contentEmptySaves => 'No worlds yet.';

  @override
  String get contentEmptyServers => 'No servers yet.';

  @override
  String contentDeleteTitle(Object name) {
    return 'Delete $name?';
  }

  @override
  String get contentDeleteBody => 'This cannot be undone.';

  @override
  String get actionDelete => 'Delete';

  @override
  String sourceAuto(String name) {
    return 'Automatic ($name first)';
  }

  @override
  String get sourceOfficial => 'Mojang';

  @override
  String get sourceBmclapi => 'BMCLAPI';

  @override
  String get catalogMods => 'Mods';

  @override
  String get catalogResourcePacks => 'Resource packs';

  @override
  String get catalogShaders => 'Shaders';

  @override
  String get catalogDataPacks => 'Data packs';

  @override
  String get catalogSearchHint => 'Search Modrinth';

  @override
  String get catalogEmpty => 'Nothing matches that.';

  @override
  String get catalogInstall => 'Install';

  @override
  String get catalogNeedsLoader => 'This version cannot take mods';

  @override
  String get catalogNeedsWorld =>
      'A data pack belongs to a world. Create or open a world first.';

  @override
  String get catalogUnknownVersion =>
      'The game version could not be read from this instance.';

  @override
  String get catalogPickWorld => 'Which world?';

  @override
  String catalogFilteredLoader(String loader, String game) {
    return '$loader · $game — matches only what can load here';
  }

  @override
  String catalogFilteredGame(String game) {
    return '$game — matches only what can load here';
  }

  @override
  String get catalogNoTarget =>
      'Select an instance on the Launch page first: content installs into one.';

  @override
  String get catalogImportWorld => 'Import world (.zip)';

  @override
  String get catalogImporting => 'Importing…';

  @override
  String catalogWorldImported(String name) {
    return 'Imported “$name”';
  }

  @override
  String catalogWorldImportFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String catalogTarget(String name) {
    return 'Installing into “$name”';
  }

  @override
  String get lanHint =>
      'Worlds this network has opened to LAN, and opening one so a friend outside can join.';

  @override
  String get lanScan => 'Find LAN worlds';

  @override
  String get lanScanning => 'Listening…';

  @override
  String get lanNothingFound =>
      'Nothing announced a world in the last few seconds.';

  @override
  String get lanUnnamedWorld => 'Unnamed world';

  @override
  String get lanOpenPort => 'Open port';

  @override
  String get lanMappingActive => 'Open to the internet';

  @override
  String get lanClosePort => 'Close port';

  @override
  String get lanNoExternalAddress =>
      'The router did not report an external address';

  @override
  String get aboutTitle => 'About';

  @override
  String get aboutVersion => 'Version';

  @override
  String get aboutCheck => 'Check for updates';

  @override
  String get aboutChecking => 'Checking…';

  @override
  String aboutUpToDate(String version) {
    return '$version is the newest version.';
  }

  @override
  String get aboutCheckFailed =>
      'Could not reach the release feed. Nothing is wrong with this install.';

  @override
  String aboutNewVersion(String version) {
    return '$version is available';
  }

  @override
  String aboutPublished(String date) {
    return 'Published $date';
  }

  @override
  String get aboutDownload => 'Download installer';

  @override
  String get aboutReleasePage => 'Release notes';

  @override
  String get setupSectionGeneral => 'General';

  @override
  String get setupSectionAppearance => 'Appearance';

  @override
  String get actionMore => 'More';

  @override
  String get actionLaunch => 'Play';

  @override
  String get detailTabOverview => 'Overview';

  @override
  String get detailTabSettings => 'Settings';

  @override
  String get contentInstall => 'Install from Modrinth';

  @override
  String get contentModsHint =>
      'Mods in this instance. A mod is switched off by renaming its jar.';

  @override
  String get contentDataPacksHint =>
      'Data packs belong to a world: pick one, then install or remove its packs.';

  @override
  String get contentEmptyMods => 'No mods yet.';

  @override
  String get contentEmptyDataPacks => 'No data packs in this world yet.';

  @override
  String get contentAddServer => 'Add server';

  @override
  String get contentServerName => 'Name';

  @override
  String get contentServerAddress => 'Address';

  @override
  String get actionSave => 'Save';
}
