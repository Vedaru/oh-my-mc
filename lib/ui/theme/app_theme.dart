import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../../data/settings.dart';

/// The accent seed and every theme derived from it.
///
/// There is exactly one place where a colour is chosen, and one colour system:
/// every widget in the app reads `Theme.of(context).colorScheme`. Two systems
/// seeded from the same value would still drift - the schemas differ - so a
/// single `ColorScheme` is a correctness property, not tidiness.
abstract final class AppTheme {
  /// The selectable accents. A launcher's accent is a user preference, not a
  /// brand statement, so the palette is short and neutral enough that every seed
  /// produces a usable surface ramp in both brightnesses.
  static const accents = <AccentChoice, m3.Color>{
    AccentChoice.blue: m3.Color(0xFF0078D4),
    AccentChoice.teal: m3.Color(0xFF00897B),
    AccentChoice.green: m3.Color(0xFF388E3C),
    AccentChoice.orange: m3.Color(0xFFEF6C00),
    AccentChoice.red: m3.Color(0xFFC62828),
    AccentChoice.purple: m3.Color(0xFF6A3AB2),
  };

  /// The seed for [choice]. Unknown values cannot occur (the enum is closed) but
  /// a null-safe lookup keeps the call sites free of `!`.
  static m3.Color seedFor(AccentChoice choice) =>
      accents[choice] ?? accents[AccentChoice.blue]!;

  /// The `ThemeData` handed to `MaterialApp`.
  ///
  /// Elevation is expressed as **tone, not shadow**: Material 3 renders a raised
  /// surface as a lighter (dark theme) or tinted (light theme) container from the
  /// same neutral ramp, so stacking surfaces never produces a drop shadow. Flutter
  /// still paints one for dialogs and menus by default, hence the zeroed
  /// elevations and the explicit container colours below - the separation is the
  /// colour step, which is the part a user should read.
  static m3.ThemeData material(
    Brightness brightness, {
    AccentChoice accent = AccentChoice.blue,
  }) {
    final scheme = m3.ColorScheme.fromSeed(
      seedColor: seedFor(accent),
      brightness: brightness,
    );
    return m3.ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      dialogTheme: m3.DialogThemeData(
        elevation: 0,
        backgroundColor: scheme.surfaceContainerHigh,
      ),
      popupMenuTheme: m3.PopupMenuThemeData(
        elevation: 0,
        color: scheme.surfaceContainer,
      ),
    );
  }

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
  static TextStyle mono(BuildContext context) => caption(context).copyWith(
    fontFamily: 'JetBrains Mono',
    fontFamilyFallback: const ['Consolas', 'DejaVu Sans Mono', 'monospace'],
    height: 1.45,
  );

  static m3.TextTheme _text(BuildContext context) =>
      m3.Theme.of(context).textTheme;

  /// The four status hues MD3 does not define.
  ///
  /// Material's `ColorScheme` has `error` but no success, warning or info role,
  /// and these four carry meaning rather than decoration: a version row is green
  /// because it is installed, not because green suits the accent. So they stay
  /// fixed instead of being seeded - a user pick of a yellow accent must not turn
  /// "installed" into something that reads as a warning. [danger] does follow the
  /// scheme's `error` so that a red accent stays consistent with dialogs.
  static ({m3.Color success, m3.Color warning, m3.Color danger, m3.Color info})
  status(BuildContext context) {
    final scheme = m3.Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return (
      success: dark ? const m3.Color(0xFF81C784) : const m3.Color(0xFF2E7D32),
      warning: dark ? const m3.Color(0xFFFFB74D) : const m3.Color(0xFFEF6C00),
      danger: scheme.error,
      info: scheme.tertiary,
    );
  }
}
