import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/ui/components/app_button.dart';
import 'package:oh_my_mc/ui/components/app_dialog.dart';

import '../../core/mc/java_catalog.dart';
import '../../core/mc/local_host.dart';
import '../../core/net/progress.dart';
import '../../data/java_providers.dart';
import '../../l10n/l10n.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';

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
    final scheme = m3.Theme.of(context).colorScheme;
    final install = ref.watch(javaProvisionControllerProvider);

    return m3.Container(
      key: const m3.ValueKey('java-panel'),
      padding: const m3.EdgeInsets.all(14),
      decoration: m3.BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: m3.BorderRadius.circular(14),
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
    final scheme = m3.Theme.of(context).colorScheme;
    return m3.Row(
      children: [
        m3.Icon(ShellIcons.download, size: 18, color: scheme.primary),
        const m3.SizedBox(width: 10),
        m3.Expanded(
          child: m3.Column(
            crossAxisAlignment: m3.CrossAxisAlignment.start,
            mainAxisSize: m3.MainAxisSize.min,
            children: [
              m3.Text(
                l10n.javaDownloadTitle(majorVersion),
                style: AppTheme.subtitle(context),
              ),
              const m3.SizedBox(height: 2),
              m3.Text(
                l10n.javaDownloadWhy(majorVersion),
                style: AppTheme.caption(context)
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const m3.SizedBox(width: 12),
        AppButton(
          key: const m3.ValueKey('java-download'),
          onPressed: () => ref
              .read(javaProvisionControllerProvider.notifier)
              .install(choice),
          style: AppButtonStyle.filled,
          label: m3.Text(l10n.javaDownloadAction(majorVersion)),
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
    final scheme = m3.Theme.of(context).colorScheme;
    final download = state.progress.download;

    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.stretch,
      children: [
        m3.Row(
          children: [
            m3.Expanded(
              child: m3.Text(
                download == null
                    ? l10n.javaDownloadExtracting
                    : l10n.javaDownloadProgress(
                        formatBytes(download.bytesDone),
                        formatBytes(download.bytesTotal),
                      ),
                style: AppTheme.subtitle(context),
              ),
            ),
            if (download?.bytesPerSecond != null)
              m3.Text(
                formatRate(download!.bytesPerSecond),
                style: AppTheme.caption(context)
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            const m3.SizedBox(width: 12),
            AppButton(
              key: const m3.ValueKey('java-cancel'),
              onPressed: () =>
                  ref.read(javaProvisionControllerProvider.notifier).cancel(),
              style: AppButtonStyle.outlined,
              size: AppButtonSize.sm,
              label: m3.Text(l10n.javaCancel),
            ),
          ],
        ),
        const m3.SizedBox(height: 8),
        m3.LinearProgressIndicator(value: state.fraction.clamp(0.0, 1.0)),
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
    return m3.Row(
      children: [
        m3.Icon(
          ShellIcons.checkCircle,
          size: 16,
          color: AppTheme.status(context).success,
        ),
        const m3.SizedBox(width: 8),
        m3.Expanded(
          child: m3.Text(
            l10n.javaDownloadDone(majorVersion),
            key: const m3.ValueKey('java-done'),
            style: AppTheme.body(context),
          ),
        ),
        AppButton(
          onPressed: () =>
              ref.read(javaProvisionControllerProvider.notifier).reset(),
          style: AppButtonStyle.text,
          size: AppButtonSize.sm,
          label: m3.Text(l10n.actionClose),
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
    return m3.Row(
      children: [
        m3.Expanded(child: m3.Text(text, style: AppTheme.body(context))),
        AppButton(
          onPressed: () =>
              ref.read(javaProvisionControllerProvider.notifier).reset(),
          style: AppButtonStyle.text,
          size: AppButtonSize.sm,
          label: m3.Text(context.l10n.actionClose),
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
    return m3.Row(
      children: [
        m3.Icon(
          ShellIcons.warning,
          size: 16,
          color: AppTheme.status(context).warning,
        ),
        const m3.SizedBox(width: 8),
        m3.Expanded(
          child: m3.Text(
            l10n.javaDownloadFailed(message),
            key: const m3.ValueKey('java-failed'),
            style: AppTheme.body(context),
          ),
        ),
        const m3.SizedBox(width: 8),
        AppButton(
          onPressed: () =>
              ref.read(javaProvisionControllerProvider.notifier).reset(),
          style: AppButtonStyle.text,
          size: AppButtonSize.sm,
          label: m3.Text(l10n.actionClose),
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
    return m3.Row(
      children: [
        m3.Icon(
          ShellIcons.checkCircle,
          size: 16,
          color: AppTheme.status(context).success,
        ),
        const m3.SizedBox(width: 8),
        m3.Text(
          context.l10n.javaUseExisting(majorVersion),
          style: AppTheme.caption(context),
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
    return m3.Row(
      children: [
        m3.Icon(
          ShellIcons.warning,
          size: 16,
          color: AppTheme.status(context).warning,
        ),
        const m3.SizedBox(width: 8),
        m3.Expanded(child: m3.Text(text, style: AppTheme.caption(context))),
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
    final scheme = m3.Theme.of(context).colorScheme;
    final runtimes = ref.watch(javaRuntimesProvider);

    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.stretch,
      mainAxisSize: m3.MainAxisSize.min,
      children: [
        m3.Row(
          children: [
            m3.Expanded(
              child: m3.Text(
                l10n.javaManagedTitle,
                style: AppTheme.subtitle(context),
              ),
            ),
            AppButton(
              key: const m3.ValueKey('java-refresh'),
              onPressed: () => ref.invalidate(javaRuntimesProvider),
              style: AppButtonStyle.text,
              size: AppButtonSize.sm,
              icon: const m3.Icon(ShellIcons.refresh, size: 14),
              label: m3.Text(l10n.javaRefresh),
            ),
          ],
        ),
        const m3.SizedBox(height: 8),
        switch (runtimes) {
          AsyncLoading() => const m3.Padding(
            padding: m3.EdgeInsets.all(12),
            child: m3.Center(child: m3.CircularProgressIndicator()),
          ),
          AsyncError(:final error) => m3.Text(
            error.toString(),
            style: AppTheme.caption(context),
          ),
          AsyncData(:final value) when value.isEmpty => m3.Text(
            l10n.javaManagedEmpty,
            key: const m3.ValueKey('java-list-empty'),
            style: AppTheme.caption(context)
                .copyWith(color: scheme.onSurfaceVariant),
          ),
          AsyncData(:final value) => m3.Column(
            mainAxisSize: m3.MainAxisSize.min,
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
    final confirmed = await m3.showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: label,
        content: m3.Text(
          major == null ? l10n.javaDelete : l10n.javaDeleteConfirm(major),
        ),
        actions: [
          AppButton(
            onPressed: () => m3.Navigator.pop(context, false),
            style: AppButtonStyle.text,
            label: m3.Text(l10n.actionCancel),
          ),
          AppButton(
            onPressed: () => m3.Navigator.pop(context, true),
            style: AppButtonStyle.filled,
            label: m3.Text(l10n.javaDeleteConfirmAction),
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
    final scheme = m3.Theme.of(context).colorScheme;
    final major = runtime.majorVersion?.majorVersion;

    return m3.Padding(
      padding: const m3.EdgeInsets.symmetric(vertical: 4),
      child: m3.Row(
        children: [
          m3.Icon(ShellIcons.java, size: 15, color: scheme.onSurfaceVariant),
          const m3.SizedBox(width: 8),
          m3.Expanded(
            child: m3.Text(
              major == null
                  ? runtime.versionName
                  : l10n.javaManagedItem(major, runtime.versionName),
              style: AppTheme.body(context),
            ),
          ),
          m3.Text(
            l10n.javaManagedDiskUse(formatBytes(runtime.diskBytes)),
            style: AppTheme.caption(context)
                .copyWith(color: scheme.onSurfaceVariant),
          ),
          const m3.SizedBox(width: 12),
          AppButton(
            key: m3.ValueKey('java-delete-${runtime.versionName}'),
            onPressed: onDelete,
            style: AppButtonStyle.text,
            size: AppButtonSize.sm,
            label: m3.Text(l10n.javaDelete),
          ),
        ],
      ),
    );
  }
}
