import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/ui/components/app_button.dart';

import '../../core/instance/instance.dart';
import '../../core/launch/launch_handle.dart';
import '../../data/instance_providers.dart';
import '../../core/mc/arch_compat.dart';
import '../../data/java_providers.dart';
import '../../data/launch_providers.dart';
import '../../l10n/l10n.dart';
import '../motion/motion.dart';
import '../instances/instance_card.dart';
import '../setup/java_panel.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';

/// The launch screen: which instance is selected, a big play button, and the
/// tail of the log.
///
/// The play button's *state* is the whole point of this screen. A launcher's
/// most common bug is a play button that stays enabled while a game is starting,
/// so the user clicks it three times and gets three JVMs; here the button is
/// driven by [LaunchSession.isBusy] and a second click is a no-op in the
/// controller as well as visually disabled.
class LaunchScreen extends ConsumerWidget {
  const LaunchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instances = ref.watch(instanceListProvider);
    final session = ref.watch(launchControllerProvider);
    final controller = ref.read(launchControllerProvider.notifier);

    final selected = switch (instances) {
      InstanceListReady(:final selected) => selected,
      _ => null,
    };

    final busy = session.isBusy;

    return MotionEntrance(
      // One cascade for the page, not one per child: the launch screen has three
      // blocks, and staggering each of their internals would take a second.
      children: [
        _Headline(instance: selected, session: session),
        _PlayRow(
          instance: selected,
          session: session,
          onPlay: selected == null || busy
              ? null
              : () => controller.launch(selected),
          onStop: session.canStop ? controller.stop : null,
        ),
        // The refusal is the useful moment to offer Java: it explains itself in
        // place, and a settings deep link at that point is a round trip the user
        // will not take.
        if (selected != null)
          _JavaOfferArea(instance: selected, session: session),
        Expanded(child: _LogTail(lines: session.log)),
      ],
    );
  }
}

/// Shows the Java panel when the last attempt was refused for want of a JVM.
///
/// Watches the requirement lazily: resolving it opens the version JSON and scans
/// for JVMs, which is wasted work for a launch that never mentioned Java.
class _JavaOfferArea extends ConsumerWidget {
  const _JavaOfferArea({required this.instance, required this.session});

  final Instance instance;
  final LaunchSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final needsJava = session.blockers.any(
      (b) =>
          b.code == BlockerCode.noRuntime || b.code == BlockerCode.javaTooOld,
    );
    if (!needsJava) return const SizedBox.shrink();

    final requirement = ref.watch(javaRequirementProvider(instance.versionId));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: requirement.when(
        loading: () => const SizedBox.shrink(),
        // A version file that cannot be read is not something the panel can
        // fix, so it reports the same "install it first" as a missing version
        // rather than leaking the exception text into the UI.
        error: (error, _) => const JavaPanel(
          requirement: JavaRequirementUnavailable(
            JavaUnavailableReason.versionNotInstalled,
          ),
        ),
        data: (value) => JavaPanel(requirement: value),
      ),
    );
  }
}

/// The instance name plus its version, animated so a selection change reads as
/// a change rather than as text swapping in place.
class _Headline extends StatelessWidget {
  const _Headline({required this.instance, required this.session});

  final Instance? instance;
  final LaunchSession session;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    final motion = MotionScope.of(context);

    final title = instance?.displayName ?? l10n.noInstanceSelected;
    final subtitle = instance == null
        ? null
        : [
            instance!.versionId,
            if (instance!.loader.isModded) instance!.loader.name,
          ].join('  ·  ');

    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.start,
      children: [
        m3.AnimatedSwitcher(
          duration: motion.of(Durations.base),
          switchInCurve: MotionCurves.enter,
          switchOutCurve: MotionCurves.exit,
          transitionBuilder: (child, animation) => m3.FadeTransition(
            opacity: animation,
            child: m3.SlideTransition(
              position: m3.Tween<m3.Offset>(
                begin: const m3.Offset(0, 0.12),
                end: m3.Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: m3.Text(
            title,
            key: m3.ValueKey(title),
            style: AppTheme.display(context),
          ),
        ),
        if (subtitle != null)
          m3.Text(
            subtitle,
            style: AppTheme.caption(context)
                .copyWith(color: scheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

class _PlayRow extends StatelessWidget {
  const _PlayRow({
    required this.instance,
    required this.session,
    required this.onPlay,
    required this.onStop,
  });

  final Instance? instance;
  final LaunchSession session;
  final VoidCallback? onPlay;
  final Future<void> Function()? onStop;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final motion = MotionScope.of(context);
    final scheme = m3.Theme.of(context).colorScheme;

    return m3.Row(
      children: [
        // Press feedback: the button gives under the pointer and springs back.
        // It reads as "heard you" on the one control the whole screen exists
        // for; motion-off returns the plain button, no listener (PLAN-M11 §3.4).
        Emphasis(
          glow: scheme.primary.withValues(alpha: 0.45),
          child: AppButton(
            key: const m3.ValueKey('play'),
            onPressed: onPlay,
            style: AppButtonStyle.filled,
            size: AppButtonSize.lg,
            // A pulsing dot, not a spinner: the launch is one indeterminate wait,
            // and a dot says "alive" without pretending to know how far along it
            // is. AmbientLoop renders its resting frame and creates no ticker
            // when motion is off.
            icon: session.isBusy
                ? AmbientLoop(
                    tween: Tween<double>(begin: 0.35, end: 1),
                    duration: Durations.slow,
                    builder: (context, value, _) => m3.Opacity(
                      opacity: value,
                      child: m3.SizedBox(
                        width: 10,
                        height: 10,
                        child: m3.DecoratedBox(
                          decoration: m3.BoxDecoration(
                            color: scheme.onPrimary,
                            shape: m3.BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  )
                : const m3.Icon(ShellIcons.play, size: 16),
            label: m3.Text(session.isBusy ? l10n.launching : l10n.playButton),
          ),
        ),
        const m3.SizedBox(width: 8),
        // The stop button only exists while something can be stopped, and it
        // fades rather than popping so the row does not jump.
        m3.AnimatedSwitcher(
          duration: motion.of(Durations.fast),
          switchInCurve: MotionCurves.enter,
          switchOutCurve: MotionCurves.exit,
          child: session.canStop
              ? AppButton(
                  key: const m3.ValueKey('stop'),
                  onPressed: onStop,
                  style: AppButtonStyle.outlined,
                  icon: const m3.Icon(ShellIcons.stop, size: 13),
                  label: m3.Text(l10n.stopButton),
                )
              : const m3.SizedBox.shrink(key: m3.ValueKey('no-stop')),
        ),
        const m3.Spacer(),
        if (session.state == LaunchState.exited)
          _ExitBadge(
            exitCode: session.exitCode,
            failure: session.failure,
            uptime: session.uptime,
          ),
      ],
    );
  }
}

class _ExitBadge extends StatelessWidget {
  const _ExitBadge({
    required this.exitCode,
    required this.failure,
    required this.uptime,
  });

  final int? exitCode;
  final LaunchFailure? failure;
  final Duration uptime;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    final failed = failure != null || (exitCode != null && exitCode != 0);

    // A non-zero exit is not necessarily an error the user can fix (the game
    // exits 1 on some crashes and on some clean quits), so the wording reports
    // the code instead of claiming a crash.
    final text = failure != null
        ? switch (failure!) {
            LaunchFailure.spawnFailed => l10n.launchFailedSpawn,
            LaunchFailure.refused => l10n.launchFailedRefused,
            LaunchFailure.prepareFailed => l10n.launchFailedPrepare,
          }
        : l10n.launchExited(exitCode ?? 0, formatPlaytime(uptime));

    final color = failed
        ? AppTheme.status(context).warning
        : scheme.onSurfaceVariant;
    return m3.Row(
      mainAxisSize: m3.MainAxisSize.min,
      children: [
        m3.Icon(
          failed ? ShellIcons.warning : ShellIcons.clock,
          size: 13,
          color: color,
        ),
        const m3.SizedBox(width: 6),
        m3.Text(text, style: AppTheme.caption(context).copyWith(color: color)),
      ],
    );
  }
}

/// The last lines of output, newest at the bottom.
///
/// Rendered as a `ListView` over the session's own bounded list: the controller
/// already keeps the newest 2000 lines, so this widget never needs to window
/// them itself. Auto-scrolling follows the tail only while the user is already at
/// the bottom, so scrolling up to read a stack trace is not undone by the next
/// log line.
class _LogTail extends StatefulWidget {
  const _LogTail({required this.lines});

  final List<LogLine> lines;

  @override
  State<_LogTail> createState() => _LogTailState();
}

class _LogTailState extends State<_LogTail> {
  final _controller = ScrollController();
  var _stickToBottom = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    // 24px of slack: "at the bottom" in practice, not mathematically.
    _stickToBottom = position.pixels >= position.maxScrollExtent - 24;
  }

  @override
  void didUpdateWidget(_LogTail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lines.length != oldWidget.lines.length && _stickToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        _controller.jumpTo(_controller.position.maxScrollExtent);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;

    if (widget.lines.isEmpty) {
      return m3.Center(
        child: m3.Text(
          l10n.logsEmpty,
          style: AppTheme.caption(context)
              .copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }

    return m3.Container(
      margin: const m3.EdgeInsets.only(top: 16),
      decoration: m3.BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: m3.BorderRadius.circular(10),
        border: m3.Border.all(color: scheme.outlineVariant),
      ),
      child: m3.ListView.builder(
        controller: _controller,
        padding: const m3.EdgeInsets.all(10),
        itemCount: widget.lines.length,
        itemBuilder: (context, index) {
          final line = widget.lines[index];
          return m3.Text(
            line.text,
            style: AppTheme.mono(context).copyWith(
              color: line.channel == LogChannel.stderr
                  ? scheme.error
                  : scheme.onSurface,
            ),
          );
        },
      ),
    );
  }
}
