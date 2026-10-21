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
}
