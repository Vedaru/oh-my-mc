import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// The resolved motion policy for a subtree.
///
/// Motion cannot be switched off by configuring either animation package:
/// `AnimationExecutor` builds an `AnimationController` and sets `value = 1.0`
/// when its limiter is inactive, and `LoopAnimationBuilder` always creates a
/// ticker. Both cost a frame and a rebuild even at zero duration. So the policy
/// is read at the widget boundary and disabled primitives skip the engine
/// entirely, returning their end state instead of animating to it.
@immutable
class Motion {
  const Motion({
    required this.curve,
    required this.enabled,
    required this.stagger,
  });

  /// Full motion, for tests and for the enabled default.
  static const Motion full = Motion(
    curve: MotionCurves.enter,
    enabled: true,
    stagger: StaggerConfig(),
  );

  /// No motion at all: every duration is zero and no ticker is created.
  static const Motion none = Motion(
    curve: MotionCurves.enter,
    enabled: false,
    stagger: StaggerConfig(),
  );

  final Curve curve;
  final bool enabled;
  final StaggerConfig stagger;

  /// Collapses [nominal] to zero when motion is disabled.
  ///
  /// Callers must pass a token from [Durations]; this is the only sanctioned
  /// way to turn a token into a duration that respects the user's setting.
  Duration of(Duration nominal) => enabled ? nominal : Duration.zero;

  /// The stagger configuration in force, already disabled when motion is off.
  StaggerConfig get effectiveStagger => stagger;
  Motion copyWith({bool? enabled, StaggerConfig? stagger}) => Motion(
    curve: curve,
    enabled: enabled ?? this.enabled,
    stagger: stagger ?? this.stagger,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Motion &&
          other.enabled == enabled &&
          other.curve == curve &&
          other.stagger == stagger;

  @override
  int get hashCode => Object.hash(enabled, curve, stagger);
}

/// Provides [Motion] to a subtree.
///
/// Two sources are OR'd and neither can *add* motion:
///
///  * `MediaQuery.disableAnimations` — the OS accessibility setting;
///  * the app's own "UI animations" preference, passed in by the shell.
///
/// This is deliberately a separate inherited widget rather than a
/// `MediaQuery` patch: the value is policy, not layout data, and reading it
/// through `MotionScope.of` makes the dependency explicit at each call site.
class MotionScope extends InheritedWidget {
  const MotionScope({required this.motion, required super.child, super.key});

  final Motion motion;

  /// Resolves the policy for [context].
  ///
  /// When no scope is present, motion is on but the OS setting still wins, so a
  /// stray widget outside the shell still honours accessibility.
  static Motion of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MotionScope>();
    final osDisables = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (scope == null) {
      return Motion.full.copyWith(enabled: !osDisables);
    }
    final motion = scope.motion;
    if (osDisables && motion.enabled) {
      return motion.copyWith(enabled: false);
    }
    return motion;
  }

  @override
  bool updateShouldNotify(MotionScope oldWidget) => oldWidget.motion != motion;
}
