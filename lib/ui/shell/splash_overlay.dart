import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../../l10n/l10n.dart';
import '../components/hover_row.dart';
import '../motion/motion.dart';
import '../theme/app_theme.dart';
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
    final scheme = m3.Theme.of(context).colorScheme;
    final motion = MotionScope.of(context);

    return m3.IgnorePointer(
      ignoring: !visible,
      child: m3.AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: motion.of(Durations.slow),
        curve: visible ? MotionCurves.enter : MotionCurves.exit,
        child: m3.ColoredBox(
          color: scheme.surface,
          child: m3.Center(
            child: m3.Column(
              mainAxisSize: m3.MainAxisSize.min,
              children: [
                AmbientLoop(
                  tween: m3.Tween<double>(begin: 0.92, end: 1.0),
                  builder: (context, scale, child) =>
                      m3.Transform.scale(scale: scale, child: child),
                  child: m3.Icon(
                    ShellIcons.instance,
                    size: 64,
                    color: scheme.primary,
                  ),
                ),
                const m3.SizedBox(height: 16),
                m3.Text(l10n.appTitle, style: AppTheme.display(context)),
                const m3.SizedBox(height: 24),
                m3.SizedBox(
                  width: 120,
                  // An indeterminate indicator is the one place the expressive
                  // progress widget cannot be trusted with reduced motion: it
                  // animates on its own schedule regardless of the setting. With
                  // motion off, a determinate bar at the last known value is a
                  // still frame that still tells the truth.
                  child: progress == null
                      ? const MotionRespectingProgressBar()
                      : m3.LinearProgressIndicator(value: progress!.clamp(0, 1)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
