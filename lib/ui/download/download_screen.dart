import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/install/version_installer.dart';
import '../../core/net/progress.dart';
import '../../core/net/version_manifest.dart';
import '../../data/install_providers.dart';
import '../../l10n/l10n.dart';
import '../motion/motion.dart';
import '../shell/shell_icons.dart';

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(
          search: _search,
          snapshots: _snapshots,
          onSnapshots: (value) => setState(() => _snapshots = value),
          onQuery: () => setState(() {}),
        ),
        if (install is! InstallIdle) _InstallPanel(state: install),
        Expanded(
          child: switch (list) {
            VersionListLoading() => const Center(child: ProgressRing()),
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
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Text(l10n.downloadVersions, style: theme.typography.title),
          const SizedBox(width: 16),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: TextBox(
                controller: search,
                placeholder: l10n.downloadSearchHint,
                prefix: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(ShellIcons.search, size: 14),
                ),
                onChanged: (_) => onQuery(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          ToggleSwitch(
            checked: snapshots,
            onChanged: onSnapshots,
            content: Text(l10n.downloadShowSnapshots),
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
    final theme = FluentTheme.of(context);

    if (versions.isEmpty) {
      return Center(
        child: Text(
          query.isEmpty
              ? l10n.downloadVersions
              : l10n.downloadSearchEmpty(query),
          key: const ValueKey('download-empty'),
          style: theme.typography.body,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stale)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: InfoBar(
              title: Text(l10n.downloadStaleCache),
              severity: InfoBarSeverity.warning,
            ),
          ),
        Expanded(
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
    final theme = FluentTheme.of(context);
    final actionable = !installed && !busy;

    return HoverButton(
      onPressed: actionable ? () => onInstall(version.id) : null,
      builder: (context, states) => Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: states.isHovered && actionable
              ? theme.resources.subtleFillColorSecondary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Icon(
                installed ? ShellIcons.check : ShellIcons.download,
                size: 16,
                color: installed
                    ? theme.resources.systemFillColorSuccess
                    : theme.inactiveColor,
              ),
            ),
            Expanded(child: Text(version.id, style: theme.typography.body)),
            Text(
              version.isRelease ? l10n.downloadRelease : l10n.downloadSnapshot,
              style: theme.typography.caption?.copyWith(
                color: theme.inactiveColor,
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 96,
              child: Text(
                installed ? l10n.downloadInstalled : '',
                textAlign: TextAlign.end,
                style: theme.typography.caption?.copyWith(
                  color: theme.resources.systemFillColorSuccess,
                ),
              ),
            ),
          ],
        ),
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
    final theme = FluentTheme.of(context);
    final notifier = ref.read(installControllerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.resources.cardBackgroundFillColorSecondary,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.resources.dividerStrokeColorDefault),
        ),
        child: switch (state) {
          InstallIdle() => const SizedBox.shrink(),
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
    final theme = FluentTheme.of(context);
    final progress = state.progress;
    final download = progress.download;
    final rate = state.bytesPerSecond;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.downloadInstalling(state.versionId),
                style: theme.typography.bodyStrong,
              ),
            ),
            Text(
              l10n.downloadStepOf(progress.step, progress.steps),
              style: theme.typography.caption?.copyWith(
                color: theme.inactiveColor,
              ),
            ),
            const SizedBox(width: 12),
            Button(
              onPressed: () =>
                  ref.read(installControllerProvider.notifier).cancel(),
              child: Text(l10n.downloadCancel),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // `null` is Fluent's indeterminate bar. A phase without a byte counter
        // (unpacking natives) would otherwise freeze a determinate bar at 0%,
        // which reads as a hang.
        ProgressBar(value: download == null ? null : state.fraction * 100),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                phaseLabel(l10n, progress.phase),
                style: theme.typography.caption,
              ),
            ),
            if (download != null) ...[
              Text(
                l10n.downloadBytes(
                  formatBytes(download.bytesDone),
                  formatBytes(download.bytesTotal),
                ),
                style: theme.typography.caption,
              ),
              if (rate != null) ...[
                const SizedBox(width: 12),
                Text(
                  // `formatRate` already appends "/s": passing it through the
                  // ".../s" message would render "1.0 MB/s/s".
                  l10n.downloadRate(formatBytes(rate.round())),
                  style: theme.typography.caption?.copyWith(
                    color: theme.inactiveColor,
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
    final theme = FluentTheme.of(context);
    final clean = problemCount == 0;
    return Row(
      children: [
        Icon(
          clean ? ShellIcons.check : ShellIcons.warning,
          size: 16,
          color: clean
              ? theme.resources.systemFillColorSuccess
              : theme.resources.systemFillColorCaution,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            clean
                ? l10n.downloadComplete(versionId)
                : l10n.downloadCompleteWithProblems(versionId, problemCount),
          ),
        ),
        Button(onPressed: onClose, child: Text(l10n.actionClose)),
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
    return Row(
      children: [
        Expanded(child: Text(text)),
        Button(onPressed: onClose, child: Text(context.l10n.actionClose)),
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
    final theme = FluentTheme.of(context);
    return Row(
      children: [
        Icon(
          ShellIcons.error,
          size: 16,
          color: theme.resources.systemFillColorCritical,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.errorDownloadFailed),
              // The installer's own text, unlocalized on purpose: it names the
              // actual cause, and a generic message would hide it.
              SelectableText(message, style: theme.typography.caption),
            ],
          ),
        ),
        Button(onPressed: onRetry, child: Text(l10n.actionRetry)),
        const SizedBox(width: 8),
        Button(onPressed: onClose, child: Text(l10n.actionClose)),
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
    final theme = FluentTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ShellIcons.error,
            size: 32,
            color: theme.resources.systemFillColorCritical,
          ),
          const SizedBox(height: 8),
          SelectableText(message, style: theme.typography.caption),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () =>
                ref.read(versionListProvider.notifier).load(forceRefresh: true),
            child: Text(l10n.downloadRetry),
          ),
        ],
      ),
    );
  }
}
