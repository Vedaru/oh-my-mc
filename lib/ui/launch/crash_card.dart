import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../../app/router.dart';
import '../../core/diagnostics/crash_analyzer.dart';
import '../../l10n/l10n.dart';
import '../../ui/theme/app_theme.dart';
import '../components/app_button.dart';
import 'crash_copy.dart';
import '../shell/shell_icons.dart';

/// 为什么会崩: the crash, in one sentence, with the button that fixes it.
///
/// This is the whole point of P6. Without it a non-zero exit is a number and a
/// console full of stack traces; with it, the page says "Out of memory - raise it
/// in 版本设置" and puts that button one click away.
class CrashCard extends StatelessWidget {
  const CrashCard({
    required this.diagnosis,
    required this.instanceId,
    this.onRetry,
    super.key,
  });

  final Diagnosis diagnosis;
  final String instanceId;

  /// Re-runs the launch. Without it the retry action is not offered: a button that
  /// does nothing is worse than one that is not there.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    final copy = CrashCopy.of(diagnosis, l10n);

    return m3.Container(
      key: const m3.ValueKey('crash-card'),
      width: double.infinity,
      padding: const m3.EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: m3.BoxDecoration(
        // A normal surface with a red marker, not a wall of red: a full
        // errorContainer block on a dark theme shouts louder than the message and
        // pulls the eye off the buttons that fix it. Colour relationship does the
        // signalling - an error-tinted icon and rule on a raised surface.
        color: scheme.surfaceContainerHigh,
        borderRadius: m3.BorderRadius.circular(14),
        border: m3.Border(left: m3.BorderSide(color: scheme.error, width: 3)),
      ),
      child: m3.Column(
        crossAxisAlignment: m3.CrossAxisAlignment.start,
        children: [
          m3.Row(
            children: [
              m3.Icon(
                ShellIcons.warning,
                size: 16,
                color: scheme.onErrorContainer,
              ),
              const m3.SizedBox(width: 8),
              m3.Expanded(
                child: m3.Text(
                  copy.title,
                  style: AppTheme.subtitle(context)
                      .copyWith(color: scheme.onErrorContainer),
                ),
              ),
            ],
          ),
          const m3.SizedBox(height: 6),
          m3.Text(
            copy.body,
            style: AppTheme.body(context)
                .copyWith(color: scheme.onErrorContainer),
          ),
          const m3.SizedBox(height: 10),
          // The evidence stays available but quiet: it is what the user pastes
          // into a help thread, not what they read first.
          m3.SelectableText(
            diagnosis.evidence,
            style: AppTheme.mono(
              context,
            ).copyWith(color: scheme.onErrorContainer.withValues(alpha: 0.85)),
          ),
          const m3.SizedBox(height: 12),
          m3.Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final action in diagnosis.actions)
                if (action != DiagnosisAction.retry || onRetry != null)
                  _Action(
                    action: action,
                    instanceId: instanceId,
                    onRetry: onRetry,
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Maps a [DiagnosisAction] onto the route that can act on it.
///
/// Every action goes somewhere that already exists - no action opens a dialog that
/// re-explains the same problem.
class _Action extends ConsumerWidget {
  const _Action({required this.action, required this.instanceId, this.onRetry});

  final DiagnosisAction action;
  final String instanceId;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final (label, route, icon) = switch (action) {
      DiagnosisAction.raiseMemory => (
        l10n.diagnosisOpenSettings,
        Routes.instanceDetail(instanceId),
        ShellIcons.settings,
      ),
      DiagnosisAction.chooseJava => (
        l10n.diagnosisChooseJava,
        Routes.setup,
        ShellIcons.java,
      ),
      DiagnosisAction.installJava => (
        l10n.diagnosisInstallJava,
        Routes.setup,
        ShellIcons.download,
      ),
      DiagnosisAction.openMods => (
        l10n.diagnosisOpenMods,
        Routes.instanceMods(instanceId),
        ShellIcons.mods,
      ),
      DiagnosisAction.openLogs => (
        l10n.diagnosisOpenLogs,
        Routes.logs,
        ShellIcons.document,
      ),
      DiagnosisAction.openDownload => (
        l10n.diagnosisOpenDownload,
        Routes.download,
        ShellIcons.download,
      ),
      DiagnosisAction.openSettings => (
        l10n.diagnosisOpenSettings,
        Routes.setup,
        ShellIcons.settings,
      ),
      // Retry is not a route: it re-runs the launch through the controller the
      // launch page owns, which is why it arrives as a callback.
      DiagnosisAction.retry => (l10n.diagnosisRetry, '', ShellIcons.play),
    };

    return AppButton(
      key: m3.ValueKey('crash-action-${action.name}'),
      onPressed: route.isEmpty ? onRetry : () => context.go(route),
      style: AppButtonStyle.text,
      size: AppButtonSize.sm,
      icon: m3.Icon(icon, size: 14),
      label: m3.Text(label),
    );
  }
}
