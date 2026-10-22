import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart' as m3e;
import 'package:material_ui/material_ui.dart' as m3;

/// The accent seed and every theme derived from it.
///
/// There is exactly one place where a colour is chosen. The Material scheme the
/// widgets use and the expressive scheme the `M3E*` components use both come
/// from [accentSeed], so a user's accent choice cannot end up applied to only
/// half the UI.
abstract final class AppTheme {
  /// Seed for both colour systems. A launcher's accent is a user preference,
  /// not a brand statement, so this is the default rather than a constant.
  static const m3.Color accentSeed = m3.Color(0xFF0078D4);

  /// The Material `ThemeData` handed to `MaterialApp`. `M3ETheme` projects its
  /// own scheme on top of this, so this exists for the widgets that read plain
  /// `Theme.of` (scrollbars, focus highlights, the selection toolbar).
  static m3.ThemeData material(Brightness brightness) => m3.ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: m3.ColorScheme.fromSeed(
      seedColor: accentSeed,
      brightness: brightness,
    ),
  );

  /// The expressive theme for `M3E*` components.
  ///
  /// `autoTheming` is false on purpose: brightness is decided by the settings
  /// value passed in, not by the platform. Leaving it on would let the OS
  /// override an explicit "always light" choice.
  static m3e.M3EThemeData expressive(Brightness brightness) =>
      m3e.M3EThemeData(
        colorScheme: m3e.M3EColorScheme.fromSeed(
          accentSeed,
          brightness: brightness,
        ),
      );

  /// Semantic type roles.
  ///
  /// Screens ask for a *role*, never a package's type scale, so replacing the
  /// design system again does not mean rewriting every `TextStyle` call site.
  /// Fluent's `caption` was 12 px, which is `labelMedium` here.
  static TextStyle title(BuildContext context) =>
      _text(context).titleMedium ?? const TextStyle();

  static TextStyle subtitle(BuildContext context) =>
      _text(context).titleSmall ?? const TextStyle();

  static TextStyle body(BuildContext context) =>
      _text(context).bodyMedium ?? const TextStyle();

  /// Metadata under a card title, timestamps, the window-chrome subtitle.
  static TextStyle caption(BuildContext context) =>
      _text(context).labelMedium ?? const TextStyle();

  /// Button and chip labels.
  static TextStyle label(BuildContext context) =>
      _text(context).labelLarge ?? const TextStyle();

  /// Headline on an empty state or a splash.
  static TextStyle display(BuildContext context) =>
      _text(context).headlineMedium ?? const TextStyle();

  /// Monospaced log output.
  ///
  /// Named families first, then `monospace`: a launcher has to run on whatever
  /// fontconfig resolves, and a single hardcoded family (the previous code used
  /// `Consolas`) renders as the default sans on any Linux box that lacks it.
  static TextStyle mono(BuildContext context) =>
      caption(context).copyWith(
        fontFamily: 'JetBrains Mono',
        fontFamilyFallback: const ['Consolas', 'DejaVu Sans Mono', 'monospace'],
        height: 1.45,
      );

  static m3.TextTheme _text(BuildContext context) =>
      m3.Theme.of(context).textTheme;
}
