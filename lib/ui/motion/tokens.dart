import 'package:flutter/widgets.dart';

/// The app's motion vocabulary: every duration and curve in one place.
///
/// Nothing outside this library may construct a raw `Duration(milliseconds:)`
/// or reference `Curves.` — `tool/check_tokens.dart` enforces that. The point is
/// not tidiness: a single source lets `MotionScope` collapse motion for users who
/// ask for it, which is impossible if durations are scattered across widgets.
abstract final class Durations {
  /// State that must feel instant: a checkbox, a hover tint.
  static const Duration xfast = Duration(milliseconds: 120);

  /// Small local feedback: press, focus ring.
  static const Duration fast = Duration(milliseconds: 200);

  /// The default for an element entering or leaving.
  static const Duration base = Duration(milliseconds: 280);

  /// Deliberate, attention-carrying transitions: page changes, drawers.
  static const Duration slow = Duration(milliseconds: 420);

  /// How long a search field waits after the last keystroke before querying.
  ///
  /// Not the same thing as an animation duration, but it lives here for the same
  /// reason the others do: it is UI timing, and scattering it across widgets is
  /// what the token rule exists to prevent.
  static const Duration debounce = Duration(milliseconds: 350);

  /// Background ambience that loops; long enough to read as "alive" rather
  /// than "moving".
  static const Duration ambient = Duration(milliseconds: 2400);
}

/// Named curves. Values match `PLAN.md` §6.1.
abstract final class MotionCurves {
  /// Decelerating. For things arriving on screen.
  static const Curve enter = Curves.easeOutCubic;

  /// Accelerating. For things leaving, so they feel like they got out of the way.
  static const Curve exit = Curves.easeInCubic;

  /// Emphasised decelerate for large surface transitions.
  static const Curve emphasise = Curves.easeOutQuint;

  /// A slight overshoot for playful, low-stakes feedback.
  static const Curve spring = Curves.easeOutBack;
}

/// Entrance-stagger budget.
///
/// The animation package has no cap: it defaults each item's delay to
/// `duration ~/ 6` and applies it cumulatively, so a 200-item grid would take
/// ~12 s to finish appearing. The budget is ours, and it is a pure function so
/// the arithmetic can be tested without pumping a single frame.
@immutable
class StaggerConfig {
  const StaggerConfig({
    this.step = const Duration(milliseconds: 40),
    this.maxTotal = const Duration(milliseconds: 320),
    this.maxAnimatedIndex = 24,
    this.itemDuration = Durations.base,
    this.curve = MotionCurves.enter,
  }) : assert(maxAnimatedIndex >= 0, 'maxAnimatedIndex must not be negative');

  /// Preferred delay between consecutive items, before the budget shrinks it.
  final Duration step;

  /// Upper bound on the delay of the *last* animated item. Longer lists get a
  /// proportionally smaller step rather than a longer entrance.
  final Duration maxTotal;

  /// Items at or past this index render at rest: the user cannot see them yet,
  /// so animating them only costs frames.
  final int maxAnimatedIndex;

  /// How long a single item takes once its delay elapses.
  final Duration itemDuration;

  final Curve curve;

  /// The delay to use between items, given how many are on screen.
  ///
  /// This shrinks [step] so the whole cascade fits inside [maxTotal]:
  /// `min(step, maxTotal ~/ animatedCount)`. The divisor is the number of items
  /// that actually animate, **not** the list length: charging the budget for
  /// items that render at rest would give a 1000-item list a sub-millisecond
  /// step, which is no cascade at all. A list of 4 keeps the full 40 ms step;
  /// 24 or more items settle at 320/24 ~= 13 ms.
  Duration stepFor(int itemCount) {
    final animated = itemCount < maxAnimatedIndex
        ? itemCount
        : maxAnimatedIndex;
    if (animated <= 1) return step;
    final cap = Duration(microseconds: maxTotal.inMicroseconds ~/ animated);
    return step < cap ? step : cap;
  }

  /// Delay before the item at [index] starts, or `Duration.zero` when the item
  /// should not animate at all.
  Duration delayFor(int index, {required int itemCount}) {
    if (!animates(index)) return Duration.zero;
    return stepFor(itemCount) * index;
  }

  /// Whether the item at [index] participates in the entrance at all.
  bool animates(int index) => index >= 0 && index < maxAnimatedIndex;
}
