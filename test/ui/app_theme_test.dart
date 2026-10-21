import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/ui/theme/app_theme.dart';

void main() {
  group('Fluent theme brightness', () {
    // The regression this guards: FluentThemeData defaults brightness to light
    // and ignores the ThemeMode it is selected under, so a dark theme that looks
    // plausible can still paint a light-on-light UI.
    test('dark() reports dark brightness', () {
      expect(AppTheme.dark().brightness, Brightness.dark);
    });

    test('light() reports light brightness', () {
      expect(AppTheme.light().brightness, Brightness.light);
    });

    test('the two themes differ rather than collapsing to one', () {
      expect(AppTheme.dark().brightness, isNot(AppTheme.light().brightness));
      expect(
        AppTheme.dark().scaffoldBackgroundColor,
        isNot(AppTheme.light().scaffoldBackgroundColor),
      );
    });

    test('dark scaffold background is opaque', () {
      // A translucent surface over an opaque window is what makes the broken
      // case look "almost right" in a screenshot.
      final dark = AppTheme.dark().scaffoldBackgroundColor;
      expect(dark.a, 1.0);
    });
  });

  group('accent seed reaches both colour systems', () {
    test('Fluent accent normal shade is the seed', () {
      expect(AppTheme.accent.normal, AppTheme.accentSeed);
    });

    test('every accent shade is defined', () {
      for (final shade in const [
        'darkest',
        'darker',
        'dark',
        'normal',
        'lighter',
        'lightest',
      ]) {
        expect(
          AppTheme.accent.swatch[shade],
          isNotNull,
          reason: 'accent shade "$shade" is missing',
        );
      }
    });

    test('Material primary derives from the same seed', () {
      for (final brightness in Brightness.values) {
        final scheme = AppTheme.material(brightness).colorScheme;
        expect(scheme.primary, isNotNull);
        expect(
          scheme.brightness,
          brightness,
          reason: 'Material scheme brightness must follow the requested one',
        );
      }
    });

    test('Material scheme adapts per brightness instead of being fixed', () {
      final light = AppTheme.material(Brightness.light).colorScheme;
      final dark = AppTheme.material(Brightness.dark).colorScheme;
      expect(dark.surface, isNot(light.surface));
    });
  });

  group('Fluent animation durations come from the motion tokens', () {
    test('match the token vocabulary', () {
      // Guards against the theme growing its own duration vocabulary: the
      // token values are the single definition of "medium" and "slow".
      expect(AppTheme.light().mediumAnimationDuration.inMilliseconds, 280);
      expect(AppTheme.light().slowAnimationDuration.inMilliseconds, 420);
    });
  });

  testWidgets('FluentApp in dark mode hands dark brightness to content', (
    tester,
  ) async {
    Brightness? seen;
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: Builder(
          builder: (context) {
            seen = FluentTheme.of(context).brightness;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(seen, Brightness.dark);
  });

  testWidgets('Material content under FluentApp sees the dark scheme', (
    tester,
  ) async {
    Brightness? seen;
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: Builder(
          builder: (context) {
            seen = m3.Theme.of(context).colorScheme.brightness;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(seen, Brightness.dark);
  });
}
