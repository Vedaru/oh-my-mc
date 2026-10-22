import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/mc/java_catalog.dart';
import '../../core/mc/local_host.dart';
import '../../core/net/progress.dart';
import '../../data/java_providers.dart';
import '../../l10n/l10n.dart';
import '../shell/shell_icons.dart';

/// The inline offer to download a Java runtime.
///
/// Shown where the launch was refused, not in a settings page: the user is at
/// the point of failure, and a link to another screen is a round trip they will
/// not take.
class JavaPanel extends ConsumerWidget {
  const JavaPanel({required this.requirement, super.key});

  /// What the version needs here: installed, downloadable, or unavailable.
  ///
  /// Passed in rather than resolved inside, because the caller already has the
  /// version JSON and the detected runtimes; resolving again here would need a
  /// second scan and could disagree with the decision that refused the launch.
  final JavaRequirement requirement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = FluentTheme.of(context);
    final install = ref.watch(javaProvisionControllerProvider);

    return Container(
      key: const ValueKey('java-panel'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorSecondary,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.resources.dividerStrokeColorDefault),
      ),
      child: switch (install) {
        JavaInstallIdle() => switch (requirement) {
          JavaRequirementSatisfied(:final runtime) => _Satisfied(
            majorVersion: runtime.majorVersion,
          ),
          JavaRequirementDownloadable(:final majorVersion) => _Offer(
            majorVersion: majorVersion,
            choice: (requirement as JavaRequirementDownloadable).choice,
          ),
          JavaRequirementUnavailable unavailable => _Unavailable(
            requirement: unavailable,
          ),
        },
        JavaInstallRunning() => _Running(state: install),
        JavaInstallDone(:final majorVersion) => _Done(
          majorVersion: majorVersion,
        ),
        JavaInstallCancelled() => _Message(
          text: context.l10n.javaDownloadCancelled,
        ),
        JavaInstallFailed(:final message) => _Failed(message: message),
      },
    );
  }
}

class _Offer extends ConsumerWidget {
  const _Offer({required this.majorVersion, required this.choice});

  final int majorVersion;
  final JavaRuntimeChoice choice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = FluentTheme.of(context);
    return Row(
      children: [
        Icon(ShellIcons.download, size: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.javaDownloadTitle(majorVersion),
                style: theme.typography.bodyStrong,
              ),
              const SizedBox(height: 2),
              Text(
                l10n.javaDownloadWhy(majorVersion),
                style: theme.typography.caption?.copyWith(
                  color: theme.inactiveColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          key: const ValueKey('java-download'),
          onPressed: () => ref
              .read(javaProvisionControllerProvider.notifier)
              .install(choice),
          child: Text(l10n.javaDownloadAction(majorVersion)),
        ),
      ],
    );
  }
}

class _Running extends ConsumerWidget {
  const _Running({required this.state});

  final JavaInstallRunning state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = FluentTheme.of(context);
    final download = state.progress.download;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                download == null
                    ? l10n.javaDownloadExtracting
                    : l10n.javaDownloadProgress(
                        formatBytes(download.bytesDone),
                        formatBytes(download.bytesTotal),
                      ),
                style: theme.typography.bodyStrong,
              ),
            ),
            if (download?.bytesPerSecond != null)
              Text(
                formatRate(download!.bytesPerSecond),
                style: theme.typography.caption?.copyWith(
                  color: theme.inactiveColor,
                ),
              ),
            const SizedBox(width: 12),
            Button(
              key: const ValueKey('java-cancel'),
              onPressed: () =>
                  ref.read(javaProvisionControllerProvider.notifier).cancel(),
              child: Text(l10n.javaCancel),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ProgressBar(value: state.fraction.clamp(0.0, 1.0)),
      ],
    );
  }
}

class _Done extends ConsumerWidget {
  const _Done({required this.majorVersion});

  final int majorVersion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = FluentTheme.of(context);
    return Row(
      children: [
        Icon(FluentIcons.completed_solid, size: 14, color: theme.accentColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l10n.javaDownloadDone(majorVersion),
            key: const ValueKey('java-done'),
            style: theme.typography.body,
          ),
        ),
        Button(
          onPressed: () =>
              ref.read(javaProvisionControllerProvider.notifier).reset(),
          child: Text(l10n.actionClose),
        ),
      ],
    );
  }
}

class _Message extends ConsumerWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = FluentTheme.of(context);
    return Row(
      children: [
        Expanded(child: Text(text, style: theme.typography.body)),
        Button(
          onPressed: () =>
              ref.read(javaProvisionControllerProvider.notifier).reset(),
          child: Text(context.l10n.actionClose),
        ),
      ],
    );
  }
}

class _Failed extends ConsumerWidget {
  const _Failed({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = FluentTheme.of(context);
    return Row(
      children: [
        Icon(
          ShellIcons.warning,
          size: 14,
          color: theme.resources.systemFillColorCaution,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l10n.javaDownloadFailed(message),
            key: const ValueKey('java-failed'),
            style: theme.typography.body,
          ),
        ),
        const SizedBox(width: 8),
        Button(
          onPressed: () =>
              ref.read(javaProvisionControllerProvider.notifier).reset(),
          child: Text(l10n.actionClose),
        ),
      ],
    );
  }
}

class _Satisfied extends StatelessWidget {
  const _Satisfied({required this.majorVersion});

  final int majorVersion;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Row(
      children: [
        Icon(FluentIcons.completed, size: 14, color: theme.accentColor),
        const SizedBox(width: 8),
        Text(
          context.l10n.javaUseExisting(majorVersion),
          style: theme.typography.caption,
        ),
      ],
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.requirement});

  final JavaRequirementUnavailable requirement;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = FluentTheme.of(context);
    final major = requirement.majorVersion;
    final text = switch (requirement.reason) {
      JavaUnavailableReason.versionNotInstalled =>
        l10n.javaUnavailableVersionMissing,
      JavaUnavailableReason.catalogUnavailable => l10n.javaUnavailableNoCatalog,
      JavaUnavailableReason.noBuildForPlatform =>
        major == null
            ? l10n.javaUnavailableNoCatalog
            : l10n.javaUnavailableNoBuild(
                major,
                javaPlatformKey(localHostOs, localHostArch),
              ),
    };
    return Row(
      children: [
        Icon(
          ShellIcons.warning,
          size: 14,
          color: theme.resources.systemFillColorCaution,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: theme.typography.caption)),
      ],
    );
  }
}

/// The list of runtimes the launcher downloaded, for the setup screen.
///
/// Separate from [JavaPanel] because this is a management list, not an offer: it
/// must work with no refusal in sight, and its only action is delete.
class JavaRuntimeList extends ConsumerWidget {
  const JavaRuntimeList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = FluentTheme.of(context);
    final runtimes = ref.watch(javaRuntimesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.javaManagedTitle,
                style: theme.typography.bodyStrong,
              ),
            ),
            Button(
              key: const ValueKey('java-refresh'),
              onPressed: () => ref.invalidate(javaRuntimesProvider),
              child: Text(l10n.javaRefresh),
            ),
          ],
        ),
        const SizedBox(height: 8),
        switch (runtimes) {
          AsyncLoading() => const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: ProgressRing()),
          ),
          AsyncError(:final error) => Text(
            error.toString(),
            style: theme.typography.caption,
          ),
          AsyncData(:final value) when value.isEmpty => Text(
            l10n.javaManagedEmpty,
            key: const ValueKey('java-list-empty'),
            style: theme.typography.caption?.copyWith(
              color: theme.inactiveColor,
            ),
          ),
          AsyncData(:final value) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final runtime in value)
                _RuntimeRow(
                  runtime: runtime,
                  onDelete: () => _confirmDelete(context, ref, runtime),
                ),
            ],
          ),
        },
      ],
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ManagedJavaRuntime runtime,
  ) async {
    final l10n = context.l10n;
    final major = runtime.majorVersion?.majorVersion;
    final label = major == null
        ? runtime.versionName
        : l10n.javaManagedItem(major, runtime.versionName);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(label),
        content: Text(
          major == null ? l10n.javaDelete : l10n.javaDeleteConfirm(major),
        ),
        actions: [
          Button(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.javaDeleteConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(javaRuntimesProvider.notifier).remove(runtime);
  }
}

class _RuntimeRow extends StatelessWidget {
  const _RuntimeRow({required this.runtime, required this.onDelete});

  final ManagedJavaRuntime runtime;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = FluentTheme.of(context);
    final major = runtime.majorVersion?.majorVersion;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(ShellIcons.java, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              major == null
                  ? runtime.versionName
                  : l10n.javaManagedItem(major, runtime.versionName),
              style: theme.typography.body,
            ),
          ),
          Text(
            l10n.javaManagedDiskUse(formatBytes(runtime.diskBytes)),
            style: theme.typography.caption?.copyWith(
              color: theme.inactiveColor,
            ),
          ),
          const SizedBox(width: 12),
          Button(
            key: ValueKey('java-delete-${runtime.versionName}'),
            onPressed: onDelete,
            child: Text(l10n.javaDelete),
          ),
        ],
      ),
    );
  }
}
