import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;

/// One grey bar of a loading placeholder.
///
/// Deliberately dumb: the *shape* lives in the screen that knows what is coming
/// (rows where rows will be, a grid where a grid will be), and this only owns
/// the corner radius and the tint. Wrap a group of them in `Skeleton` from
/// `lib/ui/motion/motion.dart` to make the group shimmer.
class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({
    required this.height,
    this.width,
    this.radius = 6,
    super.key,
  });

  /// Null stretches to the incoming constraints, which is what a text column
  /// wants.
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = m3.Theme.of(context).colorScheme;
    return m3.Container(
      width: width,
      height: height,
      decoration: m3.BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.08),
        borderRadius: m3.BorderRadius.circular(radius),
      ),
    );
  }
}
