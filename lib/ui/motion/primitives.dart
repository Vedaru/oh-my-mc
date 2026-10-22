import 'package:flutter/widgets.dart';
import 'package:flutter_staggered_animations_plus/flutter_staggered_animations_plus.dart';
import 'package:simple_animations/simple_animations.dart';

import 'motion_scope.dart';
import 'tokens.dart';

/// Which direction an item travels in from.
enum EnterFrom { below, above, left, right }

/// A single item of a staggered entrance.
///
/// Wrap a list or grid builder's child in this, passing the builder's index.
/// The index is used only to compute a delay — it is never stored, so a rebuild
/// does not restart the entrance.
///
/// The widget exists to solve two problems the package leaves open:
///
///  * the package's own `AnimationExecutor` builds a controller and sets
///    `value = 1.0` even when animations are suppressed, so "disabled" still
///    costs a frame; here the disabled path returns [child] untouched;
///  * the package has no stagger cap, so delays grow as `duration ~/ 6` per item
///    forever — [StaggerConfig] bounds the total instead.
class StaggerItem extends StatelessWidget {
  const StaggerItem({
    required this.index,
    required this.itemCount,
    required this.child,
    this.from = EnterFrom.below,
    this.distance = 24,
    this.fade = true,
    super.key,
  });

  final int index;

  /// How many items are entering together. Only used to size the step, so a
  /// long list still finishes within the budget.
  final int itemCount;

  final Widget child;
  final EnterFrom from;

  /// Travel distance in logical pixels. Kept small: a launcher's items should
  /// settle, not fly.
  final double distance;

  final bool fade;

  @override
  Widget build(BuildContext context) {
    final motion = MotionScope.of(context);
    final stagger = motion.stagger;

    // Past the cap, or with motion off: the item is already at rest. Skipping
    // the package entirely is what avoids the controller allocation.
    if (!motion.enabled || !stagger.animates(index)) {
      return child;
    }

    final delay = stagger.delayFor(index, itemCount: itemCount);

    return AnimationConfiguration.staggeredList(
      position: 0,
      duration: stagger.itemDuration,
      delay: delay,
      child: SlideAnimation(
        duration: stagger.itemDuration,
        delay: delay,
        curve: stagger.curve,
        verticalOffset: _vertical,
        horizontalOffset: _horizontal,
        child: fade ? FadeInAnimation(child: child) : child,
      ),
    );
  }

  double get _vertical => switch (from) {
    EnterFrom.below => distance,
    EnterFrom.above => -distance,
    EnterFrom.left || EnterFrom.right => 0,
  };

  double get _horizontal => switch (from) {
    EnterFrom.left => -distance,
    EnterFrom.right => distance,
    EnterFrom.below || EnterFrom.above => 0,
  };
}

/// Animates a list of items with a single bounded cascade.
///
/// Use [itemBuilder] exactly as you would with a `ListView.builder`; this wraps
/// each child, and wraps the whole list in the limiter that starts the cascade
/// on first paint rather than on every rebuild.
class StaggerList extends StatelessWidget {
  const StaggerList({
    required this.itemCount,
    required this.itemBuilder,
    this.from = EnterFrom.below,
    this.distance = 24,
    this.physics,
    this.padding,
    this.scrollDirection = Axis.vertical,
    super.key,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final EnterFrom from;
  final double distance;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry? padding;
  final Axis scrollDirection;

  @override
  Widget build(BuildContext context) {
    final motion = MotionScope.of(context);
    final body = ListView.builder(
      itemCount: itemCount,
      physics: physics,
      padding: padding,
      scrollDirection: scrollDirection,
      itemBuilder: (context, index) => RepaintBoundary(
        child: StaggerItem(
          index: index,
          itemCount: itemCount,
          from: from,
          distance: distance,
          child: itemBuilder(context, index),
        ),
      ),
    );
    if (!motion.enabled) return body;
    return AnimationLimiter(child: body);
  }
}

/// A page's block stack, entering once as a unit.
///
/// Deliberately **one** animation around the whole `Column`, not one per child:
/// wrapping children individually breaks any child that must be a direct flex
/// child (`Expanded`, `Flexible`), and a three-block page does not need a
/// cascade — the cascade budget belongs to lists ([StaggerList]).
class MotionEntrance extends StatelessWidget {
  const MotionEntrance({
    required this.children,
    this.from = EnterFrom.below,
    this.distance = 16,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final List<Widget> children;
  final EnterFrom from;
  final double distance;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final motion = MotionScope.of(context);
    final body = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );

    // Motion off returns the plain tree: no controller, no wrapper, so a
    // disabled page has exactly the render tree it would have without this
    // widget.
    if (!motion.enabled) return body;

    return AnimationLimiter(
      child: AnimationConfiguration.staggeredList(
        position: 0,
        duration: motion.stagger.itemDuration,
        child: SlideAnimation(
          duration: motion.stagger.itemDuration,
          curve: motion.stagger.curve,
          verticalOffset: switch (from) {
            EnterFrom.below => distance,
            EnterFrom.above => -distance,
            _ => 0,
          },
          horizontalOffset: switch (from) {
            EnterFrom.left => -distance,
            EnterFrom.right => distance,
            _ => 0,
          },
          child: FadeInAnimation(child: body),
        ),
      ),
    );
  }
}

/// A slow, looping ambient animation — the "alive" background layer.
///
/// When motion is disabled this renders the builder's steady-state frame once
/// and creates **no ticker**. The package cannot express that: `LoopAnimationBuilder`
/// always starts a controller, so an off-screen or motion-off loop would keep
/// scheduling frames forever.
class AmbientLoop extends StatelessWidget {
  const AmbientLoop({
    required this.builder,
    this.tween,
    this.duration = Durations.ambient,
    this.curve = Curves.linear,
    this.child,
    super.key,
  });

  /// Receives the animated value; when motion is off it receives the tween's
  /// end value, which callers must choose to be the resting appearance.
  final ValueWidgetBuilder<double> builder;

  final Tween<double>? tween;
  final Duration duration;
  final Curve curve;

  /// Passed through to [builder] unchanged. Supplying it here rather than
  /// capturing it in the closure lets the framework skip rebuilding the subtree
  /// on every tick.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final motion = MotionScope.of(context);
    final effective = tween ?? Tween<double>(begin: 0, end: 1);

    if (!motion.enabled) {
      return builder(context, effective.end ?? 1, child);
    }
    return LoopAnimationBuilder<double>(
      tween: effective,
      duration: motion.of(duration),
      curve: curve,
      builder: builder,
      child: child,
    );
  }
}
