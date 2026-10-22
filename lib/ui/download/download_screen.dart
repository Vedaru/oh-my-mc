import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/ui/components/app_button.dart';

import '../../core/install/version_installer.dart';
import '../../core/instance/instance.dart';
import '../../core/net/progress.dart';
import '../../core/net/version_manifest.dart';
import '../../data/install_providers.dart';
import '../../l10n/l10n.dart';
import '../components/app_banner.dart';
import '../components/hover_row.dart';
import '../components/page_body.dart';
import '../components/skeleton_block.dart';
import '../motion/motion.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';
import '../components/app_switch.dart';
import '../components/app_text_field.dart';

/// One manifest entry, flattened for the widget layer.
///
/// Kept separate from [ManifestVersion] so a row can be built in a test from
/// three fields instead of a 700-entry JSON fixture.
class VersionRowData {
  const VersionRowData({
    required this.id,
    required this.isRelease,
    required this.isSnapshot,
    required this.isAncient,
  });

  factory VersionRowData.of(ManifestVersion version) => VersionRowData(
    id: version.id,
    isRelease: version.isRelease,
    isSnapshot: version.isSnapshot,
    isAncient: version.isAncient,
  );

  final String id;
  final bool isRelease;
  final bool isSnapshot;
  final bool isAncient;

  /// Snapshots are listed only when the user asks, and old betas never: they
  /// cannot install without extra tooling, so an Install button for them would
  /// always fail.
  bool visible({required bool showSnapshots, required String query}) {
    if (isAncient) return false;
    if (!showSnapshots && !isRelease) return false;
    return query.isEmpty || id.toLowerCase().contains(query);
  }
}

/// The download screen: pick a version, install it, watch it happen.
///
/// One page, not a wizard. The version list is the content and the install is a
/// panel above it, because the common task is two clicks: "this one", "go".
class DownloadScreen extends ConsumerStatefulWidget {
  const DownloadScreen({super.key});

  @override
  ConsumerState<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends ConsumerState<DownloadScreen> {
  final _search = TextEditingController();
  bool _snapshots = false;
  var _loader = LoaderKind.vanilla;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final list = ref.watch(versionListProvider);
    final install = ref.watch(installControllerProvider);
    final installed = ref.watch(installedVersionsProvider);
    // Interrupted installs are *not* in `installed`: their row has to stay
    // clickable so the resume has somewhere to start.
    final incomplete = ref.watch(incompleteInstallsProvider);
    final query = _search.text.trim().toLowerCase();

    return PageBody(
      scrollable: false,
      child: m3.Column(
        crossAxisAlignment: m3.CrossAxisAlignment.stretch,
        children: [
          PageTitle(l10n.navDownload),
          _Toolbar(
            search: _search,
            snapshots: _snapshots,
            loader: _loader,
            busy: install is InstallRunning,
            onLoader: (value) => setState(() => _loader = value),
            onSnapshots: (value) => setState(() => _snapshots = value),
            onQuery: () => setState(() {}),
          ),
          if (install is! InstallIdle) _InstallPanel(state: install),
          m3.Expanded(
            child: switch (list) {
              // A skeleton, not a spinner: the row rhythm is known, so the list
              // can say "rows this size are coming" instead of "something is
              // happening" (PLAN-M11 §3.1).
              VersionListLoading() => const _VersionSkeleton(),
              VersionListFailed(:final message) => _ListFailure(
                message: message,
              ),
              VersionListReady(:final manifest, :final fromCache) => _VersionList(
                versions: [
                  for (final v in manifest.versions)
                    if (VersionRowData.of(v)
                        .visible(showSnapshots: _snapshots, query: query))
                      VersionRowData.of(v),
                ],
                query: query,
                installed: installed,
                incomplete: incomplete,
                stale: fromCache,
                // A second install while one is running would race on the same
                // `libraries/` tree; the rows are inert until it finishes.
                busy: install is InstallRunning,
                onInstall: (id) {
                  final notifier = ref.read(installControllerProvider.notifier);
                  // An interrupted install is resumed, not restarted: a restart
                  // would re-run a loader installer (minutes, and a JVM) to
                  // replace libraries that are simply missing.
                  if (incomplete.contains(id)) {
                    notifier.repair(id);
                  } else {
                    notifier.install(id, loader: _loader);
                  }
                },
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.search,
    required this.snapshots,
    required this.loader,
    required this.busy,
    required this.onLoader,
    required this.onSnapshots,
    required this.onQuery,
  });

  final TextEditingController search;
  final bool snapshots;

  /// Which loader this page installs. PCL asks the same question with a loader tab;
  /// here it sits beside the version list because the list is the same for both.
  final LoaderKind loader;

  /// A running install owns the pipeline; switching loaders mid-install would
  /// change the meaning of the row that is already downloading.
  final bool busy;

  final ValueChanged<LoaderKind> onLoader;
  final ValueChanged<bool> onSnapshots;
  final VoidCallback onQuery;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    // A Wrap, not a Row: search + loader + snapshot toggle no longer fit on one
    // line at the app's minimum window width, and an overflowing toolbar is worse
    // than a two-line one.
    return m3.Padding(
      padding: const m3.EdgeInsets.only(bottom: 12),
      child: m3.Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: m3.WrapCrossAlignment.center,
        children: [
          m3.SizedBox(
            // A fixed width, not ConstrainedBox: inside a flex an Expanded would
            // hand down tight constraints and the cap would be ignored, which is
            // how this field used to stretch across the whole page.
            width: 340,
            child: AppTextField(
              controller: search,
              hint: l10n.downloadSearchHint,
              leading: const m3.Icon(ShellIcons.search, size: 15),
              onChanged: (_) => onQuery(),
            ),
          ),
          // The loader choice belongs next to the list it applies to: the versions
          // are the same, only what gets installed around them changes.
          m3.SegmentedButton<LoaderKind>(
            key: const m3.ValueKey('download-loader'),
            // No selected-icon slot, and the same content on every segment.
            //
            // `SegmentedButton` sizes each segment to the widest *intrinsic*
            // width, so the default check mark on the selected segment made the
            // whole control change width whenever the selection moved - and here
            // it sits in a `Wrap`, so that reflowed the toolbar and changed the
            // gaps the user sees. An icon on the first segment alone had the same
            // effect. Three text labels keep the geometry identical for every
            // choice.
            showSelectedIcon: false,
            segments: [
              m3.ButtonSegment<LoaderKind>(
                value: LoaderKind.vanilla,
                label: m3.Text(l10n.loaderVanilla),
              ),
              m3.ButtonSegment<LoaderKind>(
                value: LoaderKind.fabric,
                label: m3.Text(LoaderKind.fabric.label),
              ),
              m3.ButtonSegment<LoaderKind>(
                value: LoaderKind.quilt,
                label: m3.Text(LoaderKind.quilt.label),
              ),
              // Forge and NeoForge run their own installer jar instead of
              // publishing a profile, but to the user they are one more loader in
              // the same row - which is also why the label is the brand and not
              // "installer".
              m3.ButtonSegment<LoaderKind>(
                value: LoaderKind.forge,
                label: m3.Text(LoaderKind.forge.label),
              ),
              m3.ButtonSegment<LoaderKind>(
                value: LoaderKind.neoforge,
                label: m3.Text(LoaderKind.neoforge.label),
              ),
            ],
            selected: {loader},
            // `null` disables the whole control, which is what a running install
            // needs: the row already downloading must keep its meaning.
            onSelectionChanged: busy
                ? null
                : (selection) => onLoader(selection.first),
          ),
          m3.Row(
            mainAxisSize: m3.MainAxisSize.min,
            children: [
              AppSwitch(
                value: snapshots,
                onChanged: onSnapshots,
                label: l10n.downloadShowSnapshots,
              ),
              const m3.SizedBox(width: 8),
              m3.Text(
                l10n.downloadShowSnapshots,
                style: AppTheme.body(context)
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VersionList extends StatelessWidget {
  const _VersionList({
    required this.versions,
    required this.installed,
    required this.incomplete,
    required this.busy,
    required this.stale,
    required this.query,
    required this.onInstall,
  });

  final List<VersionRowData> versions;
  final Set<String> installed;

  /// Ids whose install was interrupted. They stay clickable: the click resumes.
  final Set<String> incomplete;
  final bool busy;
  final bool stale;
  final String query;
  final void Function(String versionId) onInstall;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    if (versions.isEmpty) {
      return m3.Center(
        child: m3.Text(
          query.isEmpty
              ? l10n.downloadVersions
              : l10n.downloadSearchEmpty(query),
          key: const m3.ValueKey('download-empty'),
          style: AppTheme.body(context),
        ),
      );
    }

    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.stretch,
      children: [
        if (stale)
          m3.Padding(
            padding: const m3.EdgeInsets.only(bottom: 8),
            child: AppBanner(
              severity: BannerSeverity.warning,
              message: l10n.downloadStaleCache,
            ),
          ),
        m3.Expanded(
          child: StaggerList(
            itemCount: versions.length,
            padding: EdgeInsets.zero,
            itemBuilder: (context, index) => _VersionRow(
              version: versions[index],
              installed: installed.contains(versions[index].id),
              incomplete: incomplete.contains(versions[index].id),
              busy: busy,
              onInstall: onInstall,
            ),
          ),
        ),
      ],
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.version,
    required this.installed,
    required this.incomplete,
    required this.busy,
    required this.onInstall,
  });

  final VersionRowData version;
  final bool installed;

  /// The install started and did not finish; the files may be partial.
  final bool incomplete;
  final bool busy;
  final void Function(String versionId) onInstall;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    final success = AppTheme.status(context).success;
    // An incomplete install is actionable: that is the resume.
    final actionable = (!installed || incomplete) && !busy;

    return HoverRow(
      onTap: actionable ? () => onInstall(version.id) : null,
      builder: (hovered) => m3.Row(
        children: [
          m3.SizedBox(
            width: 28,
            child: m3.Icon(
              installed
                  ? ShellIcons.check
                  : incomplete
                  ? ShellIcons.warning
                  : ShellIcons.download,
              size: 16,
              color: installed
                  ? success
                  : incomplete
                  ? AppTheme.status(context).warning
                  : scheme.onSurfaceVariant,
            ),
          ),
          m3.Expanded(
            child: m3.Text(version.id, style: AppTheme.body(context)),
          ),
          m3.Text(
            version.isRelease ? l10n.downloadRelease : l10n.downloadSnapshot,
            style: AppTheme.caption(context)
                .copyWith(color: scheme.onSurfaceVariant),
          ),
          const m3.SizedBox(width: 16),
          m3.SizedBox(
            width: 96,
            child: m3.Text(
              installed
                  ? l10n.downloadInstalled
                  : incomplete
                  ? l10n.downloadIncomplete
                  : '',
              textAlign: m3.TextAlign.end,
              style: AppTheme.caption(context).copyWith(
                color: installed
                    ? success
                    : incomplete
                    ? AppTheme.status(context).warning
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The install in progress, or its outcome.
///
/// Stays mounted after the end so the result can be read without hunting for it;
/// the close button clears it.
class _InstallPanel extends ConsumerWidget {
  const _InstallPanel({required this.state});

  final InstallState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = m3.Theme.of(context).colorScheme;
    final motion = MotionScope.of(context);
    final notifier = ref.read(installControllerProvider.notifier);

    // The panel's state changes are the progress report: queued → running →
    // done/failed/cancelled. Switching them through an `AnimatedSwitcher` means
    // the old state *leaves* (fades and shrinks) instead of the box snapping to
    // a new height, which is what made a cancelled install look like a glitch
    // rather than an outcome.
    final panel = switch (state) {
      InstallIdle() => const m3.SizedBox.shrink(),
      InstallRunning running => _Running(state: running),
      InstallDone(:final versionId, :final problemCount) => _Done(
        versionId: versionId,
        problemCount: problemCount,
        onClose: notifier.reset,
      ),
      InstallCancelled() => _Message(
        text: context.l10n.downloadCancelled,
        onClose: notifier.reset,
      ),
      InstallFailed(:final versionId, :final message) => _Failure(
        versionId: versionId,
        message: message,
        onRetry: () => notifier.install(versionId),
        onClose: notifier.reset,
      ),
    };

    return m3.Padding(
      padding: const m3.EdgeInsets.only(bottom: 12),
      child: m3.Container(
        padding: const m3.EdgeInsets.all(16),
        decoration: m3.BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: m3.BorderRadius.circular(14),
        ),
        child: m3.AnimatedSwitcher(
          duration: motion.of(Durations.base),
          switchInCurve: MotionCurves.enter,
          switchOutCurve: MotionCurves.exit,
          transitionBuilder: (child, animation) => m3.FadeTransition(
            opacity: animation,
            child: m3.SizeTransition(
              sizeFactor: animation,
              alignment: m3.Alignment.topCenter,
              child: child,
            ),
          ),
          child: m3.KeyedSubtree(
            key: m3.ValueKey(state.runtimeType.toString()),
            child: panel,
          ),
        ),
      ),
    );
  }
}

/// The last few install-log lines, in the console face.
///
/// The phase label answers "what is it doing now"; this answers "did it start, and
/// where did it stop" - which is the question a resumed install raises, because the
/// panel that shows a phase only exists while the install is running.
class _InstallTail extends ConsumerWidget {
  const _InstallTail({this.lines = 4});

  final int lines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(installLogProvider);
    if (log.isEmpty) return const m3.SizedBox.shrink();
    final scheme = m3.Theme.of(context).colorScheme;
    final tail = log.length <= lines ? log : log.sublist(log.length - lines);

    return m3.Container(
      key: const m3.ValueKey('install-log-tail'),
      width: double.infinity,
      margin: const m3.EdgeInsets.only(top: 8),
      padding: const m3.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: m3.BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: m3.BorderRadius.circular(8),
      ),
      child: m3.Column(
        crossAxisAlignment: m3.CrossAxisAlignment.stretch,
        mainAxisSize: m3.MainAxisSize.min,
        children: [
          for (final line in tail)
            m3.Text(
              line,
              maxLines: 1,
              overflow: m3.TextOverflow.ellipsis,
              style: AppTheme.mono(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class _Running extends ConsumerWidget {
  const _Running({required this.state});

  final InstallRunning state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    final progress = state.progress;
    final download = progress.download;
    final rate = state.bytesPerSecond;

    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.stretch,
      children: [
        m3.Row(
          children: [
            m3.Expanded(
              child: m3.Text(
                l10n.downloadInstalling(state.versionId),
                style: AppTheme.subtitle(context),
              ),
            ),
            m3.Text(
              l10n.downloadStepOf(progress.step, progress.steps),
              style: AppTheme.caption(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
            const m3.SizedBox(width: 12),
            AppButton(
              onPressed: () =>
                  ref.read(installControllerProvider.notifier).cancel(),
              style: AppButtonStyle.outlined,
              size: AppButtonSize.sm,
              label: m3.Text(l10n.downloadCancel),
            ),
          ],
        ),
        const m3.SizedBox(height: 8),
        // A phase without a byte counter (unpacking natives) has no fraction, so
        // the bar goes indeterminate instead of freezing at 0%, which reads as a
        // hang.
        if (download == null)
          const MotionRespectingProgressBar()
        else
          _TrailingProgress(fraction: state.fraction),
        const m3.SizedBox(height: 6),
        m3.Row(
          children: [
            m3.Expanded(
              child: m3.Text(
                phaseLabel(l10n, progress.phase),
                style: AppTheme.caption(context),
              ),
            ),
            if (download != null) ...[
              // The percentage is the same trailing value the bar shows, as
              // digits: a bar answers "roughly how far", the number answers
              // "how much longer". It counts rather than snapping for the same
              // reason the bar trails (§3.2).
              AnimatedCount(
                value: (_displayFraction(state.fraction) * 100).floor(),
                builder: (context, percent) => m3.Text(
                  l10n.downloadPercent(percent),
                  key: const m3.ValueKey('download-percent'),
                  style: AppTheme.caption(context),
                ),
              ),
              const m3.SizedBox(width: 12),
              m3.Text(
                l10n.downloadBytes(
                  formatBytes(download.bytesDone),
                  formatBytes(download.bytesTotal),
                ),
                style: AppTheme.caption(context),
              ),
              if (rate != null) ...[
                const m3.SizedBox(width: 12),
                m3.Text(
                  // `formatRate` already appends "/s": passing it through the
                  // ".../s" message would render "1.0 MB/s/s".
                  l10n.downloadRate(formatBytes(rate.round())),
                  style: AppTheme.caption(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ],
        ),
        // What the install has actually done, not only where it is now: a resumed
        // install is otherwise indistinguishable from one that did nothing.
        const _InstallTail(),
      ],
    );
  }
}

/// Localized name for an install phase.
String phaseLabel(AppLocalizations l10n, InstallPhase phase) => switch (phase) {
  InstallPhase.manifest => l10n.downloadPhaseManifest,
  InstallPhase.versionJson => l10n.downloadPhaseVersionJson,
  InstallPhase.parents => l10n.downloadPhaseParents,
  InstallPhase.assetIndex => l10n.downloadPhaseAssetIndex,
  InstallPhase.planning => l10n.downloadPhasePlanning,
  InstallPhase.download => l10n.downloadPhaseDownload,
  InstallPhase.natives => l10n.downloadPhaseNatives,
  InstallPhase.assets => l10n.downloadPhaseAssets,
  InstallPhase.verify => l10n.downloadPhaseVerify,
};

class _Done extends StatelessWidget {
  const _Done({
    required this.versionId,
    required this.problemCount,
    required this.onClose,
  });

  final String versionId;
  final int problemCount;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = AppTheme.status(context);
    final clean = problemCount == 0;
    return m3.Row(
      children: [
        m3.Icon(
          clean ? ShellIcons.checkCircle : ShellIcons.warning,
          size: 16,
          color: clean ? status.success : status.warning,
        ),
        const m3.SizedBox(width: 8),
        m3.Expanded(
          child: m3.Text(
            clean
                ? l10n.downloadComplete(versionId)
                : l10n.downloadCompleteWithProblems(versionId, problemCount),
            style: AppTheme.body(context),
          ),
        ),
        AppButton(
          onPressed: onClose,
          style: AppButtonStyle.text,
          size: AppButtonSize.sm,
          label: m3.Text(l10n.actionClose),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.onClose});

  final String text;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return m3.Row(
      children: [
        m3.Expanded(child: m3.Text(text, style: AppTheme.body(context))),
        AppButton(
          onPressed: onClose,
          style: AppButtonStyle.text,
          size: AppButtonSize.sm,
          label: m3.Text(context.l10n.actionClose),
        ),
      ],
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({
    required this.versionId,
    required this.message,
    required this.onRetry,
    required this.onClose,
  });

  final String versionId;
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    return m3.Row(
      children: [
        m3.Icon(ShellIcons.error, size: 16, color: scheme.error),
        const m3.SizedBox(width: 8),
        m3.Expanded(
          child: m3.Column(
            crossAxisAlignment: m3.CrossAxisAlignment.start,
            children: [
              m3.Text(l10n.errorDownloadFailed, style: AppTheme.body(context)),
              // The installer's own text, unlocalized on purpose: it names the
              // actual cause, and a generic message would hide it.
              m3.SelectableText(message, style: AppTheme.caption(context)),
              const _InstallTail(lines: 3),
            ],
          ),
        ),
        AppButton(
          onPressed: onRetry,
          style: AppButtonStyle.outlined,
          size: AppButtonSize.sm,
          label: m3.Text(l10n.actionRetry),
        ),
        const m3.SizedBox(width: 8),
        AppButton(
          onPressed: onClose,
          style: AppButtonStyle.text,
          size: AppButtonSize.sm,
          label: m3.Text(l10n.actionClose),
        ),
      ],
    );
  }
}

class _ListFailure extends ConsumerWidget {
  const _ListFailure({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    return m3.Center(
      child: m3.Column(
        mainAxisSize: m3.MainAxisSize.min,
        children: [
          m3.Icon(ShellIcons.error, size: 32, color: scheme.error),
          const m3.SizedBox(height: 8),
          m3.SelectableText(message, style: AppTheme.caption(context)),
          const m3.SizedBox(height: 12),
          AppButton(
            onPressed: () =>
                ref.read(versionListProvider.notifier).load(forceRefresh: true),
            style: AppButtonStyle.filled,
            label: m3.Text(l10n.downloadRetry),
          ),
        ],
      ),
    );
  }
}

/// The version list's loading state.
///
/// Ten placeholder rows on the real row rhythm — icon gutter, name bar, type
/// bar, the fixed-width installed column — so the list does not jump when the
/// manifest arrives. A spinner here states nothing; a skeleton states "rows,
/// about this many, this tall" (PLAN-M11 §3.1).
class _VersionSkeleton extends StatelessWidget {
  const _VersionSkeleton();

  static const _rows = 10;

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: m3.ListView.builder(
        padding: m3.EdgeInsets.zero,
        // Nothing here can scroll: there is no more content to reach.
        physics: const m3.NeverScrollableScrollPhysics(),
        itemCount: _rows,
        itemBuilder: (context, index) => const m3.Padding(
          padding: m3.EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: m3.Row(
            children: [
              m3.SizedBox(
                width: 28,
                child: SkeletonBlock(width: 16, height: 16, radius: 4),
              ),
              m3.Expanded(child: SkeletonBlock(height: 12)),
              m3.SizedBox(width: 24),
              SkeletonBlock(width: 48, height: 10),
              m3.SizedBox(width: 16),
              m3.SizedBox(
                width: 96,
                child: m3.Align(
                  alignment: m3.Alignment.centerRight,
                  child: SkeletonBlock(width: 64, height: 10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The highest fraction an unfinished install may display.
///
/// One thousandth below the end keeps the bar visibly short of finished without
/// looking stuck, and keeps the percentage honest: 100% is reserved for the done
/// panel, because "100%" is the one number a user acts on.
const _incompleteProgressCeiling = 0.999;

/// [raw] clamped to what a *running* install is allowed to show.
double _displayFraction(double raw) =>
    raw.clamp(0.0, _incompleteProgressCeiling);

/// A progress bar that trails the reported fraction instead of snapping to it.
///
/// Bytes arrive in bursts, so binding the bar straight to `state.fraction` makes
/// it jump in steps. This animates toward the reported value over
/// [Durations.fast], and it is **clamped below 1.0**: an install that is still
/// running must never claim to be finished. Only the finished state may say
/// 100%, which is why the clamp lives here rather than in the caller
/// (PLAN-M11 §3.2).
class _TrailingProgress extends StatelessWidget {
  const _TrailingProgress({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final motion = MotionScope.of(context);
    final target = _displayFraction(fraction);

    return TweenAnimationBuilder<double>(
      // `begin` is replaced by the in-flight value on every rebuild, so this
      // always animates from where the bar is to where the bytes say it should
      // be.
      tween: Tween<double>(begin: target, end: target),
      duration: motion.of(Durations.fast),
      curve: MotionCurves.enter,
      builder: (context, value, _) => m3.LinearProgressIndicator(value: value),
    );
  }
}
