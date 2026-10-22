import 'package:fluent_ui/fluent_ui.dart';

import '../../core/instance/instance.dart';
import '../../l10n/l10n.dart';
import '../motion/motion.dart';
import '../shell/shell_icons.dart';

/// One instance, as a card in the grid.
///
/// The card owns no state and performs no navigation: it reports the two things
/// a user can do (select, launch) and lets the screen decide what those mean.
/// That is what lets it be tested with no router and no providers.
class InstanceCard extends StatelessWidget {
  const InstanceCard({
    required this.instance,
    required this.selected,
    required this.onTap,
    this.onPlay,
    this.busy = false,
    this.onMenu,
    super.key,
  });

  final Instance instance;
  final bool selected;
  final VoidCallback onTap;

  /// Launch this instance directly. `null` disables the button, which is what a
  /// card shows while another instance is running.
  final VoidCallback? onPlay;

  /// A launch is in flight for this instance.
  final bool busy;

  /// Opens the card's context menu. Invoked by a right click, which is where a
  /// desktop user looks for per-item actions.
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = FluentTheme.of(context);
    final motion = MotionScope.of(context);

    // Selection is a border, not a filled background: the cards carry version art
    // later, and a tint over it would fight the art.
    const radius = BorderRadius.all(Radius.circular(6));
    final borderColor = selected
        ? theme.accentColor.defaultBrushFor(theme.brightness)
        : theme.resources.controlStrokeColorDefault;

    final card = HoverButton(
      onPressed: onTap,
      focusEnabled: true,
      builder: (context, states) => AnimatedContainer(
        duration: motion.of(Durations.fast),
        curve: states.isHovered ? MotionCurves.enter : MotionCurves.exit,
        decoration: BoxDecoration(
          borderRadius: radius,
          color: theme.resources.cardBackgroundFillColorDefault,
          border: Border.all(color: borderColor, width: selected ? 2 : 1),
          boxShadow: states.isHovered
              ? [
                  BoxShadow(
                    color: theme.shadowColor.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  instance.loader.isModded
                      ? FluentIcons.puzzle
                      : ShellIcons.instance,
                  size: 20,
                  color: theme.accentColor.defaultBrushFor(theme.brightness),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    instance.displayName,
                    style: theme.typography.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(instance.versionId, style: theme.typography.caption),
                if (instance.loader.isModded) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${instance.loader.name} ${instance.loaderVersion ?? ''}'
                          .trim(),
                      style: theme.typography.caption?.copyWith(
                        color: theme.inactiveColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(ShellIcons.clock, size: 12, color: theme.inactiveColor),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    instance.lastPlayedAt == null
                        ? l10n.instanceNeverPlayed
                        : formatPlaytime(instance.totalPlaytime),
                    style: theme.typography.caption?.copyWith(
                      color: theme.inactiveColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Spacer(),
                if (busy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: ProgressRing(strokeWidth: 2),
                  )
                else
                  Button(
                    onPressed: onPlay,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(ShellIcons.play, size: 12),
                        const SizedBox(width: 4),
                        Text(l10n.playButton),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );

    final onMenu = this.onMenu;
    if (onMenu == null) return card;
    return GestureDetector(
      // Only the secondary button: a primary tap is already the card's action,
      // and long-press is not a menu gesture on desktop.
      onSecondaryTap: onMenu,
      child: card,
    );
  }
}

/// `3h 12m`, `12m`, `48s`.
///
/// Hand-formatted rather than `Duration.toString()`: `3:12:00.000000` is a debug
/// string, and this is shown next to every instance.
String formatPlaytime(Duration d) {
  if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  if (d.inMinutes >= 1) return '${d.inMinutes}m';
  return '${d.inSeconds}s';
}
