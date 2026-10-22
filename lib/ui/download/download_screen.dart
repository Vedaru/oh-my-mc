import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_3_expressive/material_3_expressive.dart' as m3e;
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/ui/components/app_button.dart';

import '../../core/install/version_installer.dart';
import '../../core/net/progress.dart';
import '../../core/net/version_manifest.dart';
import '../../data/install_providers.dart';
import '../../l10n/l10n.dart';
import '../components/app_banner.dart';
import '../components/hover_row.dart';
import '../motion/motion.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';

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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(versionListProvider);
    final install = ref.watch(installControllerProvider);
    final installed = ref.watch(installedVersionsProvider);
    final query = _search.text.trim().toLowerCase();

    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.stretch,
      children: [
        _Toolbar(
          search: _search,
          snapshots: _snapshots,
          onSnapshots: (value) => setState(() => _snapshots = value),
          onQuery: () => setState(() {}),
        ),
        if (install is! InstallIdle) _InstallPanel(state: install),
        m3.Expanded(
          child: switch (list) {
            VersionListLoading() => const m3.Center(
              child: m3.CircularProgressIndicator(),
            ),
            VersionListFailed(:final message) => _ListFailure(message: message),
            VersionListReady(:final manifest, :final fromCache) => _VersionList(
              versions: [
                for (final v in manifest.versions)
                  if (VersionRowData.of(v)
                      .visible(showSnapshots: _snapshots, query: query))
                    VersionRowData.of(v),
              ],
              query: query,
              installed: installed,
              stale: fromCache,
              // A second install while one is running would race on the same
              // `libraries/` tree; the rows are inert until it finishes.
              busy: install is InstallRunning,
              onInstall: (id) =>
                  ref.read(installControllerProvider.notifier).install(id),
            ),
          },
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.search,
    required this.snapshots,
    required this.onSnapshots,
    required this.onQuery,
  });

  final TextEditingController search;
  final bool snapshots;
  final ValueChanged<bool> onSnapshots;
  final VoidCallback onQuery;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    return m3.Padding(
      padding: const m3.EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: m3.Row(
        children: [
          m3.Text(l10n.downloadVersions, style: AppTheme.title(context)),
          const m3.SizedBox(width: 16),
          m3.Expanded(
            child: m3.ConstrainedBox(
              constraints: const m3.BoxConstraints(maxWidth: 340),
              child: m3e.M3ETextField(
                controller: search,
                placeholder: l10n.downloadSearchHint,
                leading: const m3.Icon(ShellIcons.search, size: 15),
                onChanged: (_) => onQuery(),
              ),
            ),
          ),
          const m3.SizedBox(width: 12),
          m3e.M3ESwitch(
            value: snapshots,
            onChanged: onSnapshots,
            semanticLabel: l10n.downloadShowSnapshots,
          ),
          const m3.SizedBox(width: 8),
          m3.Text(
            l10n.downloadShowSnapshots,
            style: AppTheme.body(context).copyWith(
              color: scheme.onSurfaceVariant,
            ),
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
    required this.busy,
    required this.stale,
    required this.query,
    required this.onInstall,
  });

  final List<VersionRowData> versions;
  final Set<String> installed;
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
            padding: const m3.EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: AppBanner(
              severity: BannerSeverity.warning,
              message: l10n.downloadStaleCache,
            ),
          ),
        m3.Expanded(
          child: StaggerList(
            itemCount: versions.length,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemBuilder: (context, index) => _VersionRow(
              version: versions[index],
              installed: installed.contains(versions[index].id),
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
    required this.busy,
    required this.onInstall,
  });

  final VersionRowData version;
  final bool installed;
  final bool busy;
  final void Function(String versionId) onInstall;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    final expressive = m3e.M3ETheme.of(context).colorScheme;
    final actionable = !installed && !busy;

    return HoverRow(
      onTap: actionable ? () => onInstall(version.id) : null,
      builder: (hovered) => m3.Row(
        children: [
          m3.SizedBox(
            width: 28,
            child: m3.Icon(
              installed ? ShellIcons.check : ShellIcons.download,
              size: 16,
              color: installed
                  ? expressive.success
                  : scheme.onSurfaceVariant,
            ),
          ),
          m3.Expanded(
            child: m3.Text(version.id, style: AppTheme.body(context)),
          ),
          m3.Text(
            version.isRelease ? l10n.downloadRelease : l10n.downloadSnapshot,
            style: AppTheme.caption(context).copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const m3.SizedBox(width: 16),
          m3.SizedBox(
            width: 96,
            child: m3.Text(
              installed ? l10n.downloadInstalled : '',
              textAlign: m3.TextAlign.end,
              style: AppTheme.caption(context).copyWith(
                color: expressive.success,
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
    final notifier = ref.read(installControllerProvider.notifier);

    return m3.Padding(
      padding: const m3.EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: m3.Container(
        padding: const m3.EdgeInsets.all(14),
        decoration: m3.BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: m3.BorderRadius.circular(14),
        ),
        child: switch (state) {
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
        },
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
              style: AppTheme.caption(context).copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const m3.SizedBox(width: 12),
            AppButton(
              onPressed: () =>
                  ref.read(installControllerProvider.notifier).cancel(),
              style: m3e.M3EButtonStyle.outlined,
              size: m3e.M3EButtonSize.sm,
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
          m3.LinearProgressIndicator(value: state.fraction.clamp(0.0, 1.0)),
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
                  style: AppTheme.caption(context).copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ],
        ),
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
    final scheme = m3e.M3ETheme.of(context).colorScheme;
    final clean = problemCount == 0;
    return m3.Row(
      children: [
        m3.Icon(
          clean ? ShellIcons.checkCircle : ShellIcons.warning,
          size: 16,
          color: clean ? scheme.success : scheme.warning,
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
          style: m3e.M3EButtonStyle.text,
          size: m3e.M3EButtonSize.sm,
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
          style: m3e.M3EButtonStyle.text,
          size: m3e.M3EButtonSize.sm,
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
            ],
          ),
        ),
        AppButton(
          onPressed: onRetry,
          style: m3e.M3EButtonStyle.outlined,
          size: m3e.M3EButtonSize.sm,
          label: m3.Text(l10n.actionRetry),
        ),
        const m3.SizedBox(width: 8),
        AppButton(
          onPressed: onClose,
          style: m3e.M3EButtonStyle.text,
          size: m3e.M3EButtonSize.sm,
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
            style: m3e.M3EButtonStyle.filled,
            label: m3.Text(l10n.downloadRetry),
          ),
        ],
      ),
    );
  }
}
