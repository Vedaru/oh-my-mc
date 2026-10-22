import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart' as m3e;
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/ui/theme/app_theme.dart';

void main() {
  group('brightness is decided by the caller, not the platform', () {
    // The regression this guards: a theme built without an explicit brightness
    // reports light, so a "dark" app paints a plausible light-on-light UI.
    test('the Material scheme reports the requested brightness', () {
      for (final brightness in Brightness.values) {
        expect(AppTheme.material(brightness).colorScheme.brightness, brightness);
      }
    });

    test('the expressive scheme reports the requested brightness', () {
      for (final brightness in Brightness.values) {
        expect(AppTheme.expressive(brightness).brightness, brightness);
      }
    });

    test('the two brightnesses actually differ', () {
      expect(
        AppTheme.material(Brightness.dark).colorScheme.surface,
        isNot(AppTheme.material(Brightness.light).colorScheme.surface),
      );
      expect(
        AppTheme.expressive(Brightness.dark).colorScheme.surface,
        isNot(AppTheme.expressive(Brightness.light).colorScheme.surface),
      );
    });
  });

  group('one seed reaches both colour systems', () {
    test('the expressive scheme is seeded from the shared accent', () {
      // A second seed would let a user's accent apply to half the UI: the plain
      // Material widgets and the `M3E*` ones would disagree.
      final fromSeed = m3e.M3EColorScheme.fromSeed(
        AppTheme.accentSeed,
        brightness: Brightness.light,
      );
      expect(AppTheme.expressive(Brightness.light).colorScheme.primary,
          fromSeed.primary);
    });

    test('both schemes have a primary in both modes', () {
      for (final brightness in Brightness.values) {
        expect(AppTheme.material(brightness).colorScheme.primary, isNotNull);
        expect(AppTheme.expressive(brightness).colorScheme.primary, isNotNull);
      }
    });
  });

  group('type roles', () {
    testWidgets('every role resolves to a real style', (tester) async {
      late Map<String, TextStyle> styles;
      await tester.pumpWidget(
        m3.MaterialApp(
          theme: AppTheme.material(Brightness.light),
          builder: (context, child) => m3e.M3ETheme(
            data: AppTheme.expressive(Brightness.light),
            autoTheming: false,
            child: Builder(
              builder: (context) {
                styles = {
                  'title': AppTheme.title(context),
                  'subtitle': AppTheme.subtitle(context),
                  'body': AppTheme.body(context),
                  'caption': AppTheme.caption(context),
                  'label': AppTheme.label(context),
                  'display': AppTheme.display(context),
                  'mono': AppTheme.mono(context),
                };
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      for (final entry in styles.entries) {
        expect(
          entry.value.fontSize,
          isNotNull,
          reason: 'role "${entry.key}" has no size, so it is not a real role',
        );
      }
      // Log output must survive a machine without the preferred mono font.
      expect(styles['mono']!.fontFamilyFallback, isNotEmpty);
    });
  });
}
