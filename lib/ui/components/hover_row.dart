import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../motion/motion.dart';

/// A full-width row that highlights on hover and runs [onTap] when pressed.
///
/// The launch and log screens both need a list row that looks clickable but has
/// no button chrome, and the old toolkit's `HoverButton` provided exactly that.
/// The expressive set has nothing equivalent, so this is the one copy - two
/// hand-rolled versions would drift on hover tint and hit area.
class HoverRow extends StatefulWidget {
  const HoverRow({
    required this.builder,
    this.onTap,
    this.padding = const m3.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    super.key,
  });

  /// Receives whether the pointer is over the row, so a caller can tint its own
  /// children without this widget guessing.
  final Widget Function(bool hovered) builder;

  /// Null renders the row inert: no highlight, no gesture.
  final VoidCallback? onTap;

  final m3.EdgeInsetsGeometry padding;

  @override
  State<HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<HoverRow> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final scheme = m3.Theme.of(context).colorScheme;
    final motion = MotionScope.of(context);

    final body = m3.AnimatedContainer(
      duration: motion.of(Durations.fast),
      curve: _hovered ? MotionCurves.enter : MotionCurves.exit,
      padding: widget.padding,
      decoration: m3.BoxDecoration(
        color: _hovered && enabled
            ? scheme.surfaceContainerHigh
            : m3.Colors.transparent,
        borderRadius: m3.BorderRadius.circular(8),
      ),
      child: widget.builder(_hovered && enabled),
    );

    if (!enabled) return body;
    return m3.MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: m3.GestureDetector(
        onTap: widget.onTap,
        behavior: m3.HitTestBehavior.opaque,
        child: body,
      ),
    );
  }
}

/// An indeterminate progress bar that stops moving when motion is disabled.
///
/// Material's indeterminate bar animates on its own ticker and ignores
/// `MediaQuery.disableAnimations`. With motion off this renders a determinate bar
/// at zero, which is a still frame that still communicates "working".
class MotionRespectingProgressBar extends StatelessWidget {
  const MotionRespectingProgressBar({super.key});

  @override
  Widget build(BuildContext context) {
    final enabled = MotionScope.of(context).enabled;
    return m3.LinearProgressIndicator(minHeight: 4, value: enabled ? null : 0);
  }
}
