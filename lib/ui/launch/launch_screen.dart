import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/instance/instance.dart';
import '../../core/launch/launch_handle.dart';
import '../../data/instance_providers.dart';
import '../../data/launch_providers.dart';
import '../../l10n/l10n.dart';
import '../motion/motion.dart';
import '../instances/instance_card.dart';
import '../shell/shell_icons.dart';

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
        Expanded(child: _LogTail(lines: session.log)),
      ],
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
    final theme = FluentTheme.of(context);
    final motion = MotionScope.of(context);

    final title = instance?.displayName ?? l10n.noInstanceSelected;
    final subtitle = instance == null
        ? null
        : [
            instance!.versionId,
            if (instance!.loader.isModded) instance!.loader.name,
          ].join('  ·  ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSwitcher(
          duration: motion.of(Durations.base),
          switchInCurve: MotionCurves.enter,
          switchOutCurve: MotionCurves.exit,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.12),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: Text(
            title,
            key: ValueKey(title),
            style: theme.typography.titleLarge,
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle,
            style: theme.typography.caption?.copyWith(
              color: theme.inactiveColor,
            ),
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

    return Row(
      children: [
        SizedBox(
          height: 40,
          child: FilledButton(
            onPressed: onPlay,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (session.isBusy)
                  const Padding(
                    padding: EdgeInsetsDirectional.only(end: 8),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: ProgressRing(strokeWidth: 2),
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsetsDirectional.only(end: 6),
                    child: Icon(ShellIcons.play, size: 14),
                  ),
                Text(session.isBusy ? l10n.launching : l10n.playButton),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // The stop button only exists while something can be stopped, and it
        // fades rather than popping so the row does not jump.
        AnimatedSwitcher(
          duration: motion.of(Durations.fast),
          switchInCurve: MotionCurves.enter,
          switchOutCurve: MotionCurves.exit,
          child: session.canStop
              ? Button(
                  key: const ValueKey('stop'),
                  onPressed: onStop,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(ShellIcons.stop, size: 12),
                      const SizedBox(width: 6),
                      Text(l10n.stopButton),
                    ],
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('no-stop')),
        ),
        const Spacer(),
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
    final theme = FluentTheme.of(context);
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

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          failed ? ShellIcons.warning : ShellIcons.clock,
          size: 12,
          color: failed
              ? theme.resources.systemFillColorCaution
              : theme.inactiveColor,
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: theme.typography.caption?.copyWith(
            color: failed
                ? theme.resources.systemFillColorCaution
                : theme.inactiveColor,
          ),
        ),
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
    final theme = FluentTheme.of(context);

    if (widget.lines.isEmpty) {
      return Center(
        child: Text(
          l10n.logsEmpty,
          style: theme.typography.caption?.copyWith(color: theme.inactiveColor),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorDefault,
        borderRadius: BorderRadius.circular(4),
      ),
      child: ListView.builder(
        controller: _controller,
        padding: const EdgeInsets.all(8),
        itemCount: widget.lines.length,
        itemBuilder: (context, index) {
          final line = widget.lines[index];
          return Text(
            line.text,
            style: theme.typography.caption?.copyWith(
              fontFamily: 'Consolas',
              color: line.channel == LogChannel.stderr
                  ? theme.resources.systemFillColorCritical
                  : theme.typography.caption?.color,
            ),
          );
        },
      ),
    );
  }
}
