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
  String get noInstanceSelected => 'No instance selected';

  @override
  String get instanceCreate => 'New instance';

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
  String get setupMemory => 'Memory';

  @override
  String get setupLanguage => 'Language';

  @override
  String get setupMotion => 'Animations';

  @override
  String get setupThemeMode => 'Theme';

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
  String get actionRetry => 'Retry';

  @override
  String get actionClose => 'Close';

  @override
  String get errorDownloadFailed => 'Download failed';

  @override
  String get instanceNeverPlayed => 'Never played';

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
      'Launch refused: an instance is already running.';

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
}
