import 'package:fluent_ui/fluent_ui.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../motion/motion.dart';

/// The accent seed and the two Fluent themes derived from it.
///
/// There is exactly one place where a colour is chosen. Everything else - the
/// Fluent theme, the Material theme handed to content widgets, the accent used
/// by custom-painted chrome - derives from [accentSeed], so the user's choice of
/// accent cannot end up applied to only half the UI.
abstract final class AppTheme {
  /// Seed for both colour systems. A launcher's accent is a user preference,
  /// not a brand statement, so this is the default rather than a constant.
  static const m3.Color accentSeed = m3.Color(0xFF0078D4);

  /// Fluent accent, derived from [accentSeed] so the two stay in step.
  static AccentColor get accent => AccentColor.swatch(<String, m3.Color>{
    'darkest': const m3.Color(0xFF003A66),
    'darker': const m3.Color(0xFF004E8C),
    'dark': const m3.Color(0xFF106EBE),
    'normal': accentSeed,
    'lighter': const m3.Color(0xFF2899F5),
    'lightest': const m3.Color(0xFF70C0FF),
  });

  static FluentThemeData light() => _fluent(Brightness.light);
  static FluentThemeData dark() => _fluent(Brightness.dark);

  /// Builds a Fluent theme with **both** colour systems pinned to [brightness].
  ///
  /// `FluentThemeData` defaults `brightness` to light and does not read the
  /// `ThemeMode` it is chosen under, so `darkTheme: FluentThemeData()` silently
  /// produces a light-on-light UI - including a translucent `surface` that then
  /// gets painted over an opaque background. Passing brightness explicitly, and
  /// deriving the Material theme from the same value, is the only way this stays
  /// correct; a golden test would happily record the broken result as expected.
  static FluentThemeData _fluent(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return FluentThemeData(
      brightness: brightness,
      accentColor: accent,
      // Keep Fluent's own page transitions aligned with the motion tokens, so
      // there is one definition of "slow" in the app rather than two.
      mediumAnimationDuration: Durations.base,
      slowAnimationDuration: Durations.slow,
      scaffoldBackgroundColor: isDark ? const m3.Color(0xFF111318) : null,
    );
  }

  /// The Material theme for content widgets (`material_ui`), derived from the
  /// same seed. `FluentApp` derives one internally, but doing it here keeps the
  /// mapping explicit and testable rather than implied by the framework.
  static m3.ThemeData material(Brightness brightness) => m3.ThemeData(
    useMaterial3: true,
    colorScheme: m3.ColorScheme.fromSeed(
      seedColor: accentSeed,
      brightness: brightness,
    ),
  );
}
