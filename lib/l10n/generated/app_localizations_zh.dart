// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'oh my mc';

  @override
  String get navLaunch => '启动';

  @override
  String get navInstances => '实例';

  @override
  String get navDownload => '下载';

  @override
  String get navSetup => '设置';

  @override
  String get navLogs => '日志';

  @override
  String get playButton => '启动游戏';

  @override
  String get stopButton => '停止';

  @override
  String get launching => '正在启动…';

  @override
  String get noInstanceSelected => '未选择实例';

  @override
  String get instanceCreate => '新建实例';

  @override
  String get instanceImport => '导入';

  @override
  String get instanceExport => '导出';

  @override
  String get instanceClone => '复制';

  @override
  String get instanceDelete => '删除';

  @override
  String instanceDeleteConfirm(String name) {
    return '删除 $name？此操作无法撤销。';
  }

  @override
  String instanceCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个实例',
      zero: '暂无实例',
    );
    return '$_temp0';
  }

  @override
  String get downloadVersions => '游戏版本';

  @override
  String get downloadLoaders => '模组加载器';

  @override
  String get downloadInstall => '安装';

  @override
  String get downloadInstalled => '已安装';

  @override
  String get downloadRelease => '正式版';

  @override
  String get downloadSnapshot => '快照';

  @override
  String get downloadOld => '旧版';

  @override
  String get queueTitle => '安装队列';

  @override
  String get queuePause => '暂停';

  @override
  String get queueResume => '继续';

  @override
  String get queueCancel => '取消';

  @override
  String get setupLaunch => '启动';

  @override
  String get setupJava => 'Java';

  @override
  String get setupDownload => '下载';

  @override
  String get setupUi => '界面';

  @override
  String get setupMemory => '内存';

  @override
  String get setupLanguage => '语言';

  @override
  String get setupMotion => '动画';

  @override
  String get setupThemeMode => '主题';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get logsTitle => '日志';

  @override
  String get logsEmpty => '暂无日志输出';

  @override
  String get actionRetry => '重试';

  @override
  String get actionClose => '关闭';

  @override
  String get errorDownloadFailed => '下载失败';
}
