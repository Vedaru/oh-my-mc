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

  @override
  String get instanceNeverPlayed => '从未启动';

  @override
  String get instanceNameHint => '实例名称';

  @override
  String get instancesEmpty => '还没有实例';

  @override
  String instancesSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '有 $count 个实例无法读取，已跳过',
      one: '有 1 个实例无法读取，已跳过',
    );
    return '$_temp0';
  }

  @override
  String get actionCancel => '取消';

  @override
  String get launchFailedSpawn => '无法启动 Java，请检查 Java 设置。';

  @override
  String get launchFailedRefused => '启动被拒绝，原因见日志。';

  @override
  String get launchFailedPrepare => '无法准备启动，请查看日志。';

  @override
  String launchExited(int code, String duration) {
    return '已退出，代码 $code，用时 $duration';
  }

  @override
  String get screenNotReady => '此界面尚未完成';

  @override
  String get downloadSearchHint => '搜索版本';

  @override
  String downloadSearchEmpty(String query) {
    return '没有匹配“$query”的版本';
  }

  @override
  String downloadInstalling(String version) {
    return '正在安装 $version';
  }

  @override
  String get downloadPhaseManifest => '读取版本列表';

  @override
  String get downloadPhaseVersionJson => '读取版本元数据';

  @override
  String get downloadPhaseParents => '读取继承的元数据';

  @override
  String get downloadPhaseAssetIndex => '读取资源索引';

  @override
  String get downloadPhasePlanning => '整理下载清单';

  @override
  String get downloadPhaseDownload => '下载中';

  @override
  String get downloadPhaseNatives => '解压本地库';

  @override
  String get downloadPhaseAssets => '放置资源文件';

  @override
  String get downloadPhaseVerify => '校验文件';

  @override
  String downloadStepOf(int step, int steps) {
    return '第 $step 步，共 $steps 步';
  }

  @override
  String downloadBytes(String done, String total) {
    return '$done / $total';
  }

  @override
  String downloadRate(String rate) {
    return '$rate/秒';
  }

  @override
  String downloadComplete(String version) {
    return '$version 已可开始游戏';
  }

  @override
  String downloadCompleteWithProblems(String version, int count) {
    return '$version 已安装，但有 $count 个文件需要修复';
  }

  @override
  String get downloadCancel => '取消安装';

  @override
  String get downloadCancelled => '安装已取消';

  @override
  String get downloadSourceOfficial => '官方源';

  @override
  String get downloadSourceBmclapi => 'BMCLAPI 镜像';

  @override
  String get downloadShowSnapshots => '显示快照';

  @override
  String get downloadStaleCache => '当前离线，版本列表可能不是最新';

  @override
  String get downloadRetry => '重新加载';

  @override
  String javaDownloadTitle(int major) {
    return '需要 Java $major';
  }

  @override
  String javaDownloadWhy(int major) {
    return '该版本需要 Java $major，但本机没有找到。';
  }

  @override
  String javaDownloadAction(int major) {
    return '下载并安装';
  }

  @override
  String javaDownloadProgress(String done, String total) {
    return '$done（共 $total）';
  }

  @override
  String get javaDownloadExtracting => '正在解压…';

  @override
  String javaDownloadDone(int major) {
    return 'Java $major 已就绪';
  }

  @override
  String get javaUnavailableVersionMissing =>
      '请先安装该版本，启动器需要它的版本文件来判断所需的 Java 版本。';

  @override
  String get javaUnavailableNoCatalog => '无法获取 Java 运行时目录，请检查网络后重试。';

  @override
  String javaUnavailableNoBuild(int major, String platform) {
    return '本系统（$platform）没有发布可用的 Java $major 版本，请手动安装。';
  }

  @override
  String get javaManagedTitle => '已下载的 Java 运行时';

  @override
  String get javaManagedEmpty => '尚未下载任何 Java 运行时。';

  @override
  String javaManagedItem(int major, String version) {
    return 'Java $major（$version）';
  }

  @override
  String javaManagedDiskUse(String size) {
    return '占用 $size';
  }

  @override
  String get javaDelete => '删除';

  @override
  String javaDeleteConfirm(int major) {
    return '删除 Java $major？需要它的实例将无法启动，直到重新下载。';
  }

  @override
  String get javaDeleteConfirmAction => '删除';

  @override
  String get javaRefresh => '刷新';

  @override
  String get javaCancel => '取消';

  @override
  String get javaDownloadCancelled => '已取消 Java 下载';

  @override
  String javaDownloadFailed(String reason) {
    return 'Java 下载失败：$reason';
  }

  @override
  String javaUseExisting(int major) {
    return '已在本机找到 Java $major';
  }

  @override
  String javaUnavailableOnPlatform(int major) {
    return '此平台没有可用的 Java $major。';
  }

  @override
  String javaUnavailableDetail(int major, String platform) {
    return 'Mojang 没有为 $platform 发布 Java $major。你可以自行安装，并在实例设置中指向它。';
  }
}
