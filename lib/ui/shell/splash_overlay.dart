import 'package:fluent_ui/fluent_ui.dart';

import '../../l10n/l10n.dart';
import '../motion/motion.dart';
import 'shell_icons.dart';

/// The first screen the app paints, before the shell exists.
///
/// Two jobs: cover the gap while settings and the instance list load, and give
/// the app a moment of its own before it becomes a launcher. It therefore fades
/// **itself** out — the shell is mounted underneath from the first frame, so the
/// splash never owns a navigation decision and cannot strand the user if loading
/// is slow.
///
/// The wordmark uses [AmbientLoop] rather than a `Future.delayed`: motion-off
/// renders the resting frame with no ticker at all, which a delayed callback
/// cannot do.
class SplashOverlay extends StatelessWidget {
  const SplashOverlay({
    required this.progress,
    required this.visible,
    super.key,
  });

  /// 0..1. Drives the ring; indeterminate when the caller has no estimate.
  final double? progress;

  /// When false the overlay fades out and stops taking pointer events.
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = FluentTheme.of(context);
    final motion = MotionScope.of(context);

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: motion.of(Durations.slow),
        curve: visible ? MotionCurves.enter : MotionCurves.exit,
        child: ColoredBox(
          color: theme.scaffoldBackgroundColor,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AmbientLoop(
                  tween: Tween(begin: 0.92, end: 1.0),
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: Icon(
                    ShellIcons.instance,
                    size: 64,
                    color: theme.accentColor.defaultBrushFor(theme.brightness),
                  ),
                ),
                const SizedBox(height: 16),
                Text(l10n.appTitle, style: theme.typography.titleLarge),
                const SizedBox(height: 24),
                SizedBox(
                  width: 120,
                  child: progress == null
                      ? const ProgressBar()
                      : ProgressBar(value: progress!.clamp(0, 1) * 100),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
