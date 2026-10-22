import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/ui/components/app_button.dart';

import '../../core/instance/instance.dart';
import '../../l10n/l10n.dart';
import '../motion/motion.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';

/// One instance, as a card in the grid.
///
/// The card owns no state and performs no navigation: it reports the two things
/// a user can do (select, launch) and lets the screen decide what those mean.
/// That is what lets it be tested with no router and no providers.
class InstanceCard extends StatefulWidget {
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
  State<InstanceCard> createState() => _InstanceCardState();
}

class _InstanceCardState extends State<InstanceCard> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    final motion = MotionScope.of(context);

    // Selection is an outline, not a fill: the cards carry version art later, and
    // a tint over it would fight the art. Unselected cards carry no outline at
    // all - the same filled surface the settings sections use, so a page is one
    // material rather than a set of boxes.
    final radius = m3.BorderRadius.circular(16);

    final card = m3.MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: m3.GestureDetector(
        onTap: widget.onTap,
        // Only the secondary button: a primary tap is already the card's action,
        // and long-press is not a menu gesture on desktop.
        onSecondaryTap: widget.onMenu,
        child: m3.AnimatedContainer(
          duration: motion.of(Durations.fast),
          curve: _hovered ? MotionCurves.enter : MotionCurves.exit,
          decoration: m3.BoxDecoration(
            borderRadius: radius,
            color: _hovered
                ? scheme.surfaceContainerHigh
                : scheme.surfaceContainerLow,
            border: widget.selected
                ? m3.Border.all(color: scheme.primary, width: 2)
                : null,
          ),
          padding: const m3.EdgeInsets.all(16),
          child: m3.Column(
            crossAxisAlignment: m3.CrossAxisAlignment.start,
            mainAxisSize: m3.MainAxisSize.min,
            children: [
              m3.Row(
                children: [
                  // The tag is what makes the icon fly into the detail header.
                  m3.Hero(
                    tag: instanceHeroTag(widget.instance.id),
                    child: m3.Icon(
                      widget.instance.loader.isModded
                          ? ShellIcons.addon
                          : ShellIcons.instance,
                      size: 22,
                      color: scheme.primary,
                    ),
                  ),
                  const m3.SizedBox(width: 10),
                  m3.Expanded(
                    child: m3.Text(
                      widget.instance.displayName,
                      style: AppTheme.subtitle(context),
                      maxLines: 1,
                      overflow: m3.TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const m3.SizedBox(height: 8),
              m3.Row(
                children: [
                  m3.Text(
                    widget.instance.versionId,
                    style: AppTheme.caption(context),
                  ),
                  if (widget.instance.loader.isModded) ...[
                    const m3.SizedBox(width: 6),
                    m3.Flexible(
                      child: m3.Text(
                        '${widget.instance.loader.name} '
                                '${widget.instance.loaderVersion ?? ''}'
                            .trim(),
                        style: AppTheme.caption(context)
                            .copyWith(color: scheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: m3.TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              const m3.SizedBox(height: 12),
              m3.Row(
                children: [
                  m3.Icon(
                    ShellIcons.clock,
                    size: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                  const m3.SizedBox(width: 5),
                  // Expanded, not Flexible + Spacer: the Spacer claimed the free
                  // space first and squeezed this label into "Never pla…".
                  m3.Expanded(
                    child: m3.Text(
                      widget.instance.lastPlayedAt == null
                          ? l10n.instanceNeverPlayed
                          : formatPlaytime(widget.instance.totalPlaytime),
                      style: AppTheme.caption(context)
                          .copyWith(color: scheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: m3.TextOverflow.ellipsis,
                    ),
                  ),
                  const m3.SizedBox(width: 8),
                  if (widget.busy)
                    // Determinate-looking and still: an indeterminate spinner is
                    // the one widget that keeps a ticker alive with motion off,
                    // and the card is not the place to spend that.
                    m3.SizedBox(
                      width: 20,
                      height: 20,
                      child: m3.CircularProgressIndicator(
                        value: 0.35,
                        strokeWidth: 2.5,
                        color: scheme.primary,
                      ),
                    )
                  else
                    AppButton(
                      onPressed: widget.onPlay,
                      style: AppButtonStyle.filled,
                      size: AppButtonSize.sm,
                      icon: const m3.Icon(ShellIcons.play, size: 13),
                      label: m3.Text(l10n.playButton),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return card;
  }
}

/// The `Hero` tag shared by a card's icon and the detail screen's header.
String instanceHeroTag(String instanceId) => 'instance-icon-$instanceId';

/// `3h 12m`, `12m`, `48s`.
///
/// Hand-formatted rather than `Duration.toString()`: `3:12:00.000000` is a debug
/// string, and this is shown next to every instance.
String formatPlaytime(Duration d) {
  if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  if (d.inMinutes >= 1) return '${d.inMinutes}m';
  return '${d.inSeconds}s';
}
