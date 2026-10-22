import 'package:flutter/widgets.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_staggered_animations_plus/flutter_staggered_animations_plus.dart';
import 'package:simple_animations/simple_animations.dart';
import 'package:skeletonizer/skeletonizer.dart';

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
        // Slide only, no page-wide fade. An `Opacity` over the whole page forces a
        // save-layer every frame, so the compositor re-rasterises the entire
        // window to move it a few pixels - which is exactly what "the animation
        // runs at a low frame rate" looks like on a 1440x900 page holding a grid
        // or a log. A transform is free by comparison, and the entrance still
        // reads as an arrival.
        //
        // The boundary is what makes the transform free: without one, every
        // frame of the slide repaints the subtree, which is a fullscreen page's
        // ten megapixels at this app's pixel ratio.
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
          child: RepaintBoundary(child: body),
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

/// A held emphasis: the control shrinks while the pointer is down and springs
/// back on release.
///
/// This is the "the control heard you" state from `PLAN-M11` §3.4 — the Play
/// button's `1 → 0.97 → 1`. It listens with [Listener] rather than a gesture
/// detector, so it never competes for the tap its child is waiting for.
///
/// With motion disabled it returns [child] and installs **no listener**: no
/// controller, no frames, and no changing tap area. The disabled tree is
/// exactly the tree the caller wrote.
///
/// There is no glow: Material 3 draws depth with tone, not with a shadow or a
/// halo, and a coloured halo under a filled button is exactly the effect the
/// spec avoids.
class Emphasis extends StatefulWidget {
  const Emphasis({required this.child, this.scale = 0.97, super.key});

  final Widget child;

  /// How far the child shrinks while held. `1` disables the scale.
  final double scale;

  @override
  State<Emphasis> createState() => _EmphasisState();
}

class _EmphasisState extends State<Emphasis> {
  var _held = false;

  void _setHeld(bool value) {
    if (_held == value) return;
    setState(() => _held = value);
  }

  @override
  Widget build(BuildContext context) {
    final motion = MotionScope.of(context);
    if (!motion.enabled) return widget.child;

    return Listener(
      onPointerDown: (_) => _setHeld(true),
      onPointerUp: (_) => _setHeld(false),
      onPointerCancel: (_) => _setHeld(false),
      child: AnimatedScale(
        scale: _held ? widget.scale : 1,
        duration: Durations.xfast,
        curve: MotionCurves.spring,
        child: widget.child,
      ),
    );
  }
}

/// A number that counts to its new value instead of snapping to it.
///
/// Used where the number *is* the answer — the memory a launch will ask for, the
/// percentage of a download. The tween is ours rather than a package's: the
/// digit-slide packages all pull `package:flutter/material.dart` (the banned
/// second tree) to animate ~15 lines of arithmetic.
///
/// Motion disabled renders the final value directly; no ticker is created.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({required this.value, required this.builder, super.key});

  final int value;

  /// Receives the in-flight value. Rebuilding the label here (rather than
  /// animating a `Text` in place) keeps localization in the caller's hands.
  final Widget Function(BuildContext context, int value) builder;

  @override
  Widget build(BuildContext context) {
    final motion = MotionScope.of(context);
    if (!motion.enabled) return builder(context, value);

    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: value, end: value),
      duration: motion.of(Durations.base),
      curve: MotionCurves.emphasise,
      builder: (context, animated, _) => builder(context, animated),
    );
  }
}

/// The loading idiom: a placeholder laid out like the content that is coming.
///
/// Wrap the **placeholder**, never the real content — Skeletonizer paints over
/// its subtree and hides semantics while it does.
///
/// Note `enabled: motion.enabled` rather than dropping the wrapper: with motion
/// off the bones still draw (a still frame that says "loading") and
/// `Skeletonizer` never builds its controller, which is the property
/// `test/ui/motion_informative_test.dart` asserts.
class Skeleton extends StatelessWidget {
  const Skeleton({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = MotionScope.of(context);
    return Skeletonizer(enabled: motion.enabled, child: child);
  }
}

/// A one-shot tint for a row that has just been appended.
///
/// The log console appends lines while the user watches; without this a warning
/// arrives as a silent text change in a wall of text. The tint starts opaque and
/// fades to nothing on the frame the row enters, then the row looks like every
/// other row.
///
/// `flutter_animate` builds its controller unconditionally, so this wrapper is
/// the only place in `lib/` allowed to import it (enforced by
/// `tool/check_imports.dart`), and motion-off returns [child] untouched.
class AppendHighlight extends StatelessWidget {
  const AppendHighlight({
    required this.child,
    required this.enabled,
    this.tint,
    super.key,
  });

  final Widget child;

  /// Whether this row just arrived. A row that was already on screen must not
  /// re-run the effect, or every rebuild would flash the whole console.
  final bool enabled;

  /// Tint colour, usually `AppTheme.status(context).warning`.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final motion = MotionScope.of(context);
    final tintColor = tint;
    if (!motion.enabled || !enabled || tintColor == null) return child;

    return Animate(
      effects: [
        // A fade of the overlay only: the row itself is faded in by the list's
        // own transition, and two fades on one arrival read as a stutter.
        TintEffect(
          color: tintColor,
          begin: 1,
          end: 0,
          duration: Durations.slow,
          curve: MotionCurves.exit,
        ),
      ],
      child: child,
    );
  }
}
