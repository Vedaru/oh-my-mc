/// Motion foundation. The only library in `lib/` that may reference raw
/// durations, curves or the animation packages.
///
/// Content code imports this file and nothing else from `lib/ui/motion/src/`:
/// the indirection is what makes swapping an engine a one-file change.
library;

export 'motion_scope.dart';
export 'primitives.dart';
export 'tokens.dart';
