import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart' as m3e;
import 'package:material_ui/material_ui.dart' as m3;

/// An expressive button whose label is always visible.
///
/// `M3EButton` only builds its `label` when an `icon` is also present; with a
/// label and no icon it falls back to `child`, so a text-only button renders as
/// an empty pill. Passing the content as `child` sidesteps that entirely, and the
/// label inherits the button's own text style because it is left unstyled.
class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    this.onPressed,
    this.icon,
    this.style = m3e.M3EButtonStyle.filled,
    this.size = m3e.M3EButtonSize.sm,
    this.semanticLabel,
    this.tooltip,
    super.key,
  });

  final Widget label;

  /// Null disables the button, which is what a pending install relies on.
  final VoidCallback? onPressed;

  final Widget? icon;
  final m3e.M3EButtonStyle style;
  final m3e.M3EButtonSize size;
  final String? semanticLabel;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    return m3e.M3EButton(
      onPressed: onPressed,
      style: style,
      size: size,
      semanticLabel: semanticLabel,
      tooltip: tooltip,
      child: icon == null
          ? label
          : m3.Row(
              mainAxisSize: m3.MainAxisSize.min,
              children: [
                icon,
                const m3.SizedBox(width: 8),
                m3.Flexible(child: label),
              ],
            ),
    );
  }
}
