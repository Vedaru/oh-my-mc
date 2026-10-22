import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/ui/components/app_button.dart';
import 'package:oh_my_mc/ui/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester, Widget button) => tester.pumpWidget(
  m3.MaterialApp(
    theme: AppTheme.material(Brightness.light),
    home: m3.Scaffold(body: m3.Center(child: button)),
  ),
);

void main() {
  group('size maps to an MD3 role, not the expressive geometry', () {
    // Measured from the expressive button this replaces: `sm` rendered 48 px
    // (a 40 px body plus Material's tap-target padding) and `lg` rendered 96.
    // `sm` is unchanged; `lg` deliberately adopts MD3's large role, because a
    // 96 px pill would be the one control visibly outside the design system.
    testWidgets('sm renders at the same 48 px as before', (tester) async {
      await _pump(
        tester,
        AppButton(label: const m3.Text('Play'), onPressed: () {}),
      );
      expect(tester.getSize(find.byType(m3.FilledButton)).height, 48);
    });

    testWidgets('lg adopts the MD3 large role at 56 px', (tester) async {
      await _pump(
        tester,
        AppButton(
          label: const m3.Text('Play'),
          size: AppButtonSize.lg,
          onPressed: () {},
        ),
      );
      expect(tester.getSize(find.byType(m3.FilledButton)).height, 56);
    });
  });

  group('style selects the button role', () {
    testWidgets('filled, outlined and text are distinct widgets', (
      tester,
    ) async {
      for (final (style, type) in [
        (AppButtonStyle.filled, m3.FilledButton),
        (AppButtonStyle.outlined, m3.OutlinedButton),
        (AppButtonStyle.text, m3.TextButton),
      ]) {
        await _pump(
          tester,
          AppButton(label: const m3.Text('x'), style: style, onPressed: () {}),
        );
        expect(find.byType(type), findsOneWidget);
      }
    });
  });

  group('the label is never dropped', () {
    // The regression: the previous button only built `label` when an icon was
    // present, so a text-only button rendered as an empty pill.
    testWidgets('a label with no icon still renders text', (tester) async {
      await _pump(tester, AppButton(label: const m3.Text('Install')));
      expect(find.text('Install'), findsOneWidget);
    });

    testWidgets('a label with an icon renders both', (tester) async {
      await _pump(
        tester,
        AppButton(
          label: const m3.Text('Install'),
          icon: const m3.Icon(m3.Icons.add),
          onPressed: () {},
        ),
      );
      expect(find.text('Install'), findsOneWidget);
      expect(find.byType(m3.Icon), findsOneWidget);
    });
  });

  group('disabled state', () {
    testWidgets('a null callback disables the button', (tester) async {
      await _pump(tester, AppButton(label: const m3.Text('Install')));
      final button = tester.widget<m3.FilledButton>(
        find.byType(m3.FilledButton),
      );
      expect(button.enabled, isFalse);
    });

    testWidgets(
      'a semanticLabel replaces the visual label for screen readers',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(
          tester,
          AppButton(
            label: const m3.Icon(m3.Icons.close),
            semanticLabel: 'Close',
            onPressed: () {},
          ),
        );
        expect(find.bySemanticsLabel('Close'), findsOneWidget);
        handle.dispose();
      },
    );
  });
}
