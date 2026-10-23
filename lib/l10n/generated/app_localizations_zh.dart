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
  String get navExpand => '展开导航栏';

  @override
  String get navCollapse => '收起导航栏';

  @override
  String get playButton => '启动游戏';

  @override
  String get stopButton => '停止';

  @override
  String get launching => '正在启动…';

  @override
  String get launchRunning => '运行中';

  @override
  String get launchStarting => '启动中';

  @override
  String get noInstanceSelected => '未选择实例';

  @override
  String get launchEmptyHint => '先在「实例」页新建一个，再回到这里启动。';

  @override
  String get launchVersionListTitle => '版本列表';

  @override
  String get launchVersionListEmpty => '还没有安装任何版本。去下载页装一个。';

  @override
  String get launchVersionSettings => '版本设置';

  @override
  String get launchManageInstances => '管理实例';

  @override
  String get launchNewInstance => '新建实例';

  @override
  String get instanceCreate => '新建实例';

  @override
  String get instanceVersionLabel => '版本';

  @override
  String get instanceNoVersions => '还没有安装任何游戏版本';

  @override
  String get instanceNoVersionsHint => '实例必须绑定一个已安装的版本。请先在「下载」页安装一个。';

  @override
  String get instanceImport => '导入';

  @override
  String get instanceExport => '导出';

  @override
  String get instanceClone => '复制';

  @override
  String instanceCloneFailed(String error) {
    return '复制失败：$error';
  }

  @override
  String get instanceDelete => '删除';

  @override
  String instanceDeleteConfirm(String name) {
    return '删除 $name？此操作无法撤销。';
  }

  @override
  String instanceDeleteConfirmFiles(String name) {
    return '删除 $name？其文件夹及其中所有内容都会被移除，此操作无法撤销。';
  }

  @override
  String instanceDeleteFilesFailed(String path) {
    return '已从列表中移除该实例，但无法删除其文件夹，请手动删除：$path';
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
  String get loaderVanilla => '原版';

  @override
  String get downloadInstall => '安装';

  @override
  String get downloadInstalled => '已安装';

  @override
  String get downloadIncomplete => '未完成';

  @override
  String get installLogCopy => '复制安装日志';

  @override
  String get installLogCopied => '已复制安装日志';

  @override
  String get launchRepairTitle => '安装没有完成';

  @override
  String get launchRepairMissingTitle => '这个版本还没有安装';

  @override
  String launchRepairMissingBody(String version) {
    return '$version 已经不在磁盘上了，重新安装后才能启动这个实例。';
  }

  @override
  String launchRepairBody(int count) {
    return '缺少 $count 个文件，这个版本无法启动。继续安装只会补下缺失的部分。';
  }

  @override
  String get launchRepairAction => '继续安装';

  @override
  String get launchMissingVersionAction => '去安装';

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
  String get setupAccent => '主题色';

  @override
  String get setupAccentHint => '整个界面的配色都由它生成，浅色与深色主题都会跟随。';

  @override
  String get accentBlue => '蓝色';

  @override
  String get accentTeal => '青色';

  @override
  String get accentGreen => '绿色';

  @override
  String get accentOrange => '橙色';

  @override
  String get accentRed => '红色';

  @override
  String get accentPurple => '紫色';

  @override
  String get setupMemory => '内存';

  @override
  String get setupLanguage => '语言';

  @override
  String get setupThemeMode => '主题';

  @override
  String get setupThemeHint => '跟随系统的明暗变化。';

  @override
  String get setupLanguageHint => '简体与繁体中文均使用中文翻译。';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => '中文';

  @override
  String get setupPlayerName => '玩家名称';

  @override
  String get setupPlayerNameHint => '3-16 个字母、数字或下划线。';

  @override
  String get setupMemoryHint => '供未单独设置内存的实例使用。';

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
  String get launchLogEmptyHint => '启动游戏后，日志会显示在这里。';

  @override
  String get logsSearchHint => '搜索日志';

  @override
  String get logsOnlyErrors => '仅错误';

  @override
  String get logsSessionCurrent => '当前会话';

  @override
  String logsLineCount(int count) {
    return '$count 行';
  }

  @override
  String get logsSessionHistory => '历史会话';

  @override
  String get logsSessionEmpty => '还没有保存的会话日志。';

  @override
  String get logsOpenFolder => '打开日志文件夹';

  @override
  String get logsNoMatches => '没有符合筛选条件的日志。';

  @override
  String get logsCopy => '复制';

  @override
  String get actionRetry => '重试';

  @override
  String get actionClose => '关闭';

  @override
  String get errorDownloadFailed => '下载失败';

  @override
  String get instanceNeverPlayed => '从未启动';

  @override
  String get instanceOpen => '打开设置';

  @override
  String get instanceMissing => '这个实例已不存在。';

  @override
  String get actionBack => '返回';

  @override
  String get instanceSectionGeneral => '常规';

  @override
  String get instanceSectionRuntime => 'Java 与内存';

  @override
  String get instanceSectionWindow => '窗口';

  @override
  String get instanceWindowWidth => '宽度';

  @override
  String get instanceWindowHeight => '高度';

  @override
  String get instanceWindowHint => '留空则使用游戏默认的窗口大小。';

  @override
  String get instanceFullscreen => '全屏';

  @override
  String get instanceFolderMods => '模组';

  @override
  String get instanceFolderResourcePacks => '资源包';

  @override
  String get instanceFolderShaderPacks => '光影';

  @override
  String get instanceFolderSaves => '存档';

  @override
  String get instanceSectionFiles => '文件';

  @override
  String get modsTitle => '模组';

  @override
  String modsCounts(int enabled, int total) {
    return '已启用 $enabled / 共 $total';
  }

  @override
  String get modsSearchHint => '搜索 Modrinth';

  @override
  String get modsRefresh => '刷新';

  @override
  String get modsOpenFolder => '打开文件夹';

  @override
  String get modsSearchTitle => '安装模组';

  @override
  String get modsSearchEmpty => '没有匹配的模组。';

  @override
  String modsSearchFiltered(String loader, String game) {
    return '$loader · $game — 只显示能在这里加载的';
  }

  @override
  String get modsSearchNeedsLoader => '这个版本无法安装模组';

  @override
  String get modsSearchVanillaHint =>
      '请先为这个游戏版本安装 Fabric、Quilt、Forge 或 NeoForge，模组需要加载器。';

  @override
  String get modsInstall => '安装';

  @override
  String get modsGet => '获取模组';

  @override
  String get modsDisabled => '已禁用';

  @override
  String get modsDeleteTitle => '删除这个模组？';

  @override
  String modsDeleteBody(String name) {
    return '$name 会从 mods 文件夹里删除。';
  }

  @override
  String get modsDeleteAction => '删除';

  @override
  String get modsEmptyTitle => '还没有模组';

  @override
  String get modsEmptyBody => '把 .jar 放进 mods 文件夹，或从下载页获取。';

  @override
  String modsToggleFailed(String reason) {
    return '无法修改模组：$reason';
  }

  @override
  String get modsManageHint => 'mods/ · 点击管理';

  @override
  String get instanceFilesHint => '版本目录和四个内容文件夹，点一行即可打开。';

  @override
  String instanceFolderItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 项',
      one: '1 项',
      zero: '空',
    );
    return '$_temp0';
  }

  @override
  String get instanceOpenFolderTooltip => '打开文件夹';

  @override
  String get instanceCopyPath => '复制路径';

  @override
  String get instancePathCopied => '已复制路径';

  @override
  String get instanceSectionArguments => '参数';

  @override
  String get instanceJvmArgsLabel => 'JVM 参数';

  @override
  String get instanceJvmArgsHint => '每行一个，在游戏启动前传给 Java，例如 -XX:+UseG1GC';

  @override
  String get instanceGameArgsLabel => '游戏参数';

  @override
  String get instanceGameArgsHint => '每行一个，直接传给游戏，例如 --fullscreen';

  @override
  String instanceArgsPreview(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个参数',
      zero: '没有额外参数',
    );
    return '$_temp0';
  }

  @override
  String instanceArgsPreviewList(String args) {
    return '将传入：$args';
  }

  @override
  String get instanceNameLabel => '名称';

  @override
  String get instanceIsolationLabel => '独立游戏目录';

  @override
  String get instanceIsolationHint => '切换后已有文件不会被移动。';

  @override
  String get instanceIsolationEmpty =>
      '此实例将使用一个空白文件夹。共享文件夹中已有的世界、模组和设置会留在原处，不会被复制或移动。';

  @override
  String get instanceIsolationOn => '独立目录';

  @override
  String get instanceIsolationOff => '共享目录';

  @override
  String get instanceMemoryLabel => '内存';

  @override
  String get instanceMemoryHint => '关闭时使用全局默认值。';

  @override
  String instanceMemoryUsingDefault(int mb) {
    return '使用默认值（$mb MB）';
  }

  @override
  String instanceMemoryMb(int mb) {
    return '$mb MB';
  }

  @override
  String get instanceMemoryBigger => '内存更大不一定更快：堆越大，垃圾回收一次耗时越久。';

  @override
  String get instanceJavaLabel => 'Java';

  @override
  String get instanceJavaHint => '指定这个实例由哪个 Java 运行。';

  @override
  String get instanceJavaAutomatic => '自动（按版本选择）';

  @override
  String get instanceJavaTest => '测试';

  @override
  String get instanceJavaTestRunning => '正在检查…';

  @override
  String instanceJavaTestOk(int major, String version, String vendor) {
    return '可用：Java $major，$version，$vendor';
  }

  @override
  String get instanceJavaTestNoVendor => '未标注的供应商';

  @override
  String get instanceJavaTestHint => '运行此文件，确认它能启动并报告版本。';

  @override
  String get instanceJavaTestFailed => '该文件未能以 Java 运行时身份响应，请换一个，或重新下载。';

  @override
  String get instanceJavaNoneDownloaded => '还没有下载过 Java 运行时，可前往「设置」获取。';

  @override
  String get instanceJavaHintDetail => '这里只列出本启动器下载的运行时。';

  @override
  String get instancePlaytimeLabel => '游戏时长';

  @override
  String instancePlaytimeValue(String duration, String date) {
    return '共 $duration，上次游玩 $date';
  }

  @override
  String get instancePathLabel => '游戏目录';

  @override
  String get instanceOpenFolderFailed => '无法打开该目录。';

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
  String downloadPercent(int percent) {
    return '$percent%';
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
  String get javaDirsTitle => 'Java 目录';

  @override
  String get javaDirsHint => '版本需要时启动器会自己安装 Java；这里可以补充你已有的 JDK 目录。';

  @override
  String get javaAddDir => '添加目录…';

  @override
  String get javaRemoveDir => '移除';

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

  @override
  String get packImport => '导入整合包';

  @override
  String get packImporting => '正在导入…';

  @override
  String packImported(String name, int count) {
    return '已导入「$name」· $count 个文件';
  }

  @override
  String packImportFailed(String error) {
    return '导入失败：$error';
  }

  @override
  String get packExport => '导出整合包';

  @override
  String packExported(int count, String path) {
    return '已导出 $count 个文件到 $path';
  }

  @override
  String packExportFailed(String error) {
    return '导出失败：$error';
  }

  @override
  String get diagnosisOpenSettings => '版本设置';

  @override
  String get diagnosisChooseJava => '选择 Java';

  @override
  String get diagnosisInstallJava => '安装 Java';

  @override
  String get diagnosisOpenMods => '模组';

  @override
  String get diagnosisOpenLogs => '日志';

  @override
  String get diagnosisOpenDownload => '下载';

  @override
  String get diagnosisRetry => '再试一次';

  @override
  String get settingsNetworkTitle => '网络';

  @override
  String get settingsNetworkHint => '测量启动器用到的下载源速度，并显示局域网联机要用的地址。';

  @override
  String get settingsSpeedTest => '测试下载速度';

  @override
  String get settingsSpeedTesting => '测试中…';

  @override
  String get settingsLanAddress => '局域网地址';

  @override
  String get settingsLanUnknown => '没有找到可用的网络接口';

  @override
  String get settingsCopy => '复制';

  @override
  String get settingsCopied => '已复制';

  @override
  String get diagOutOfMemoryTitle => '内存不足';

  @override
  String get diagOutOfMemoryBody =>
      '游戏把堆内存用尽了。加了模组的 1.20 通常需要 4 GB 或更多，在版本设置里调高内存即可；如果机器没有更多内存，就只能减少模组。另外 32 位 Java 需要换成 64 位。';

  @override
  String get diagOutOfMetaspaceTitle => '元空间不足';

  @override
  String get diagOutOfMetaspaceBody =>
      '这不是游戏堆内存：JVM 的类元数据用尽了。提高内存滑块没有用 —— 这是旧版 Java 配上大型整合包，换成 Java 17 或 21。';

  @override
  String get diagJavaTooOldTitle => 'Java 版本太低';

  @override
  String get diagJavaTooOldBody =>
      '游戏或模组里的类是用更新的 Java 编译的。在版本设置里换一个更新的运行时，或者让启动器安装一个。';

  @override
  String diagJavaTooOldNamedTitle(int java) {
    return '这个版本需要 Java $java';
  }

  @override
  String diagJavaTooOldNamedBody(int java) {
    return '当前 Java 低于游戏或模组要求的 Java $java。在版本设置里选择 Java $java，或者让启动器安装一个。';
  }

  @override
  String get diagJavaMissingTitle => '找不到 Java 运行时';

  @override
  String get diagJavaMissingBody =>
      '配置的 Java 已经不在那个路径了 —— 被移动过，或者启动器管理的运行时被删掉了。换一个，或者安装一个。';

  @override
  String get diagModConflictTitle => '模组组合冲突';

  @override
  String get diagModConflictBody =>
      '加载器拒绝了这套模组：两个模组提供了同样的东西，或者某个模组需要的另一个模组版本没装。日志里会点名涉及的模组。';

  @override
  String get diagModMismatchTitle => '模组与游戏版本不匹配';

  @override
  String get diagModMismatchBody =>
      '模组要用的类不存在。加了模组的实例里，通常是模组是给别的 Minecraft 版本编译的；原版实例里则是安装文件不完整。';

  @override
  String get diagMissingDependencyTitle => '模组缺少前置';

  @override
  String get diagMissingDependencyBody =>
      '某个模组需要另一个没安装的模组。装上缺的那个就行 —— 搜索对话框会自动带上依赖。';

  @override
  String get diagMixinFailedTitle => '模组注入失败';

  @override
  String get diagMixinFailedBody =>
      'mixin 没能应用，几乎总是因为模组是给别的游戏或加载器版本编译的。删除或更新那个模组。';

  @override
  String diagMixinFailedNamedTitle(String mod) {
    return '模组注入失败：$mod';
  }

  @override
  String diagMixinFailedNamedBody(String mod) {
    return '$mod 的 mixin 没能应用，几乎总是因为它给别的游戏或加载器版本编译的。删除或更新这个模组。';
  }

  @override
  String get diagArchMismatchTitle => '原生库与系统不匹配';

  @override
  String get diagArchMismatchBody =>
      'LWJGL 加载不了原生代码，通常是 64 位系统上用了 32 位 Java（或反过来），也可能是别的启动器解压的原生库。重装这个版本，并确认 Java 是 64 位。';

  @override
  String get diagGraphicsDriverTitle => '显卡驱动崩溃';

  @override
  String get diagGraphicsDriverBody =>
      'Minecraft 无法创建或使用 OpenGL 上下文。更新显卡驱动；笔记本上还要确认游戏没有跑在只支持不了 OpenGL 3.2 的显卡上。';

  @override
  String get diagNetworkFailureTitle => '下载失败';

  @override
  String get diagNetworkFailureBody => '有文件没能下载下来。重试一次；如果一直失败，就是这个网络访问不到该下载源。';

  @override
  String get diagCorruptInstallTitle => '安装文件损坏';

  @override
  String get diagCorruptInstallBody =>
      '有 jar 读不出来 —— 通常是下载中断或磁盘满了。修复版本只会重下没通过校验的文件。';

  @override
  String diagUnknownTitle(String code) {
    return '游戏以代码 $code 退出';
  }

  @override
  String get diagUnknownBody => '没有匹配到已知的失败模式。去看日志末尾：退出前最后一个异常通常就是原因。';

  @override
  String get contentResourcePacks => '资源包';

  @override
  String get contentShaderPacks => '光影';

  @override
  String get contentSaves => '存档';

  @override
  String get contentServers => '服务器';

  @override
  String get contentResourcePacksHint => '启用的资源包会写进 options.txt，游戏启动时读取。';

  @override
  String get contentShaderPacksHint => '已安装的光影包；在游戏里选择启用的那个。';

  @override
  String get contentSavesHint => '这个实例的存档。删除后无法恢复。';

  @override
  String get contentServersHint => '游戏里多人游戏列表显示的内容。';

  @override
  String get contentEmptyResourcePacks => '还没有资源包。';

  @override
  String get contentEmptyShaderPacks => '还没有光影包。';

  @override
  String get contentEmptySaves => '还没有存档。';

  @override
  String get contentEmptyServers => '还没有服务器。';

  @override
  String contentDeleteTitle(Object name) {
    return '删除「$name」？';
  }

  @override
  String get contentDeleteBody => '这个操作无法撤销。';

  @override
  String get contentAddServer => '添加服务器';

  @override
  String get contentServerName => '名称';

  @override
  String get contentServerAddress => '地址，例如 play.example.com';

  @override
  String get actionDelete => '删除';

  @override
  String get actionSave => '保存';

  @override
  String sourceAuto(String name) {
    return '自动（优先 $name）';
  }

  @override
  String get sourceOfficial => 'Mojang';

  @override
  String get sourceBmclapi => 'BMCLAPI';

  @override
  String get sourceTitle => '下载源';

  @override
  String get catalogMods => '模组';

  @override
  String get catalogResourcePacks => '资源包';

  @override
  String get catalogShaders => '光影';

  @override
  String get catalogDataPacks => '数据包';

  @override
  String get catalogSearchHint => '搜索 Modrinth';

  @override
  String get catalogEmpty => '没有匹配的内容。';

  @override
  String get catalogInstall => '安装';

  @override
  String get catalogNeedsLoader => '这个版本无法安装模组';

  @override
  String get catalogNeedsWorld => '数据包属于某一个存档。请先创建或打开一个存档。';

  @override
  String get catalogUnknownVersion => '读不出这个实例的游戏版本。';

  @override
  String get catalogPickWorld => '安装到哪个存档？';

  @override
  String catalogFilteredLoader(String loader, String game) {
    return '$loader · $game — 只显示能在这里加载的';
  }

  @override
  String catalogFilteredGame(String game) {
    return '$game — 只显示能在这里加载的';
  }

  @override
  String get catalogNoTarget => '先在「启动」里选一个实例：内容要装进某个实例。';

  @override
  String get catalogImportWorld => '导入世界（.zip）';

  @override
  String get catalogImporting => '正在导入…';

  @override
  String catalogWorldImported(String name) {
    return '已导入「$name」';
  }

  @override
  String catalogWorldImportFailed(String error) {
    return '导入失败：$error';
  }

  @override
  String catalogTarget(String name) {
    return '安装到「$name」';
  }

  @override
  String get lanHint => '这个网络里开了局域网的世界；也可以把其中一个开放到外网，让不在同一网络的朋友进来。';

  @override
  String get lanScan => '查找局域网世界';

  @override
  String get lanScanning => '正在监听…';

  @override
  String get lanNothingFound => '最近几秒内没有世界在广播。';

  @override
  String get lanUnnamedWorld => '未命名世界';

  @override
  String get lanOpenPort => '开放端口';

  @override
  String get lanMappingActive => '已开放到外网';

  @override
  String get lanClosePort => '关闭端口';

  @override
  String get lanNoExternalAddress => '路由器没有报告外网地址';

  @override
  String get aboutTitle => '关于';

  @override
  String get aboutVersion => '版本';

  @override
  String get aboutCheck => '检查更新';

  @override
  String get aboutChecking => '检查中…';

  @override
  String aboutUpToDate(String version) {
    return '$version 已是最新版本。';
  }

  @override
  String get aboutCheckFailed => '连不上发布源。这次安装本身没有问题。';

  @override
  String aboutNewVersion(String version) {
    return '有新版本 $version';
  }

  @override
  String aboutPublished(String date) {
    return '发布于 $date';
  }

  @override
  String get aboutDownload => '下载安装包';

  @override
  String get aboutReleasePage => '更新说明';
}
