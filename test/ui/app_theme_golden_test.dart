import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/ui/theme/app_theme.dart';

/// Renders the resolved colours of a theme as solid swatches.
///
/// Deliberately no text: a golden containing glyphs depends on the host's font
/// rendering, so it fails on a different machine for reasons unrelated to the
/// theme. Solid rectangles are pixel-identical everywhere, which keeps this test
/// about the one thing it should be about - whether dark mode actually resolves
/// to dark colours.
Widget _swatches(FluentThemeData theme) {
  final m3Scheme = AppTheme.material(theme.brightness).colorScheme;
  final colors = <m3.Color>[
    theme.scaffoldBackgroundColor,
    theme.accentColor.normal,
    theme.resources.controlFillColorDefault,
    m3Scheme.primary,
    m3Scheme.surface,
    m3Scheme.onSurface,
  ];

  return Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(
      color: theme.brightness == Brightness.dark
          ? const m3.Color(0xFF000000)
          : const m3.Color(0xFFFFFFFF),
      child: Column(
        children: [
          for (final color in colors) Expanded(child: ColoredBox(color: color)),
        ],
      ),
    ),
  );
}

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light()),
    ('dark', AppTheme.dark()),
  ]) {
    testWidgets('theme swatches - $name', (tester) async {
      tester.view.physicalSize = const Size(240, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_swatches(theme));
      await expectLater(
        find.byType(ColoredBox).first,
        matchesGoldenFile('goldens/theme_$name.png'),
      );
    });
  }
}
