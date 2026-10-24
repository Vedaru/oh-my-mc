import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../theme/app_theme.dart';

/// A card that *is* an action: an icon, what it does, one line about how, and a button.
///
/// The download page used to express these as a row of five pills, which spent the page's
/// width on five words and left a line of explanation to do all the work. A card carries
/// the icon and the sentence together, and a grid of them fills a wide window instead of
/// leaving a quarter of it empty.
///
/// Hover raises the surface one tone step (MD3, no shadow); [onPressed] null disables the
/// whole card - tapping it does nothing and it says so by losing the accent, not by
/// looking broken.
class ActionCard extends StatefulWidget {
  const ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onPressed,
    this.width = 288,
    super.key,
  });

  final m3.IconData icon;
  final String title;
  final String subtitle;

  /// The button's label. Absent means the whole card is the button.
  final String? actionLabel;

  final VoidCallback? onPressed;
  final double width;

  @override
  State<ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<ActionCard> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = m3.Theme.of(context).colorScheme;
    final enabled = widget.onPressed != null;
    final accent = enabled ? scheme.onSurface : scheme.onSurfaceVariant;

    return m3.MouseRegion(
      cursor: enabled
          ? m3.SystemMouseCursors.click
          : m3.SystemMouseCursors.basic,
      onHover: (event) => setState(() => _hovered = true),
      onExit: (event) => setState(() => _hovered = false),
      child: m3.GestureDetector(
        onTap: enabled ? widget.onPressed : null,
        child: m3.Container(
          width: widget.width,
          padding: const m3.EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: m3.BoxDecoration(
            // Hover is a tone step, not a border: the same rule the rest of the app
            // follows for every raised surface.
            color: _hovered && enabled
                ? scheme.surfaceContainerHigh
                : scheme.surfaceContainerLow,
            borderRadius: m3.BorderRadius.circular(16),
          ),
          child: m3.Column(
            crossAxisAlignment: m3.CrossAxisAlignment.start,
            mainAxisSize: m3.MainAxisSize.min,
            children: [
              m3.Icon(widget.icon, size: 20, color: accent),
              const m3.SizedBox(height: 10),
              m3.Text(
                widget.title,
                style: AppTheme.body(context)
                    .copyWith(color: accent, fontWeight: m3.FontWeight.w500),
              ),
              const m3.SizedBox(height: 4),
              m3.Text(
                widget.subtitle,
                style: AppTheme.caption(context)
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
              if (widget.actionLabel case final label?) ...[
                const m3.SizedBox(height: 10),
                m3.Text(
                  label,
                  style: AppTheme.caption(context).copyWith(
                    color: enabled ? scheme.primary : scheme.onSurfaceVariant,
                    fontWeight: m3.FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
