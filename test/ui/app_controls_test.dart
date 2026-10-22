import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/ui/components/app_dialog.dart';
import 'package:oh_my_mc/ui/components/app_radio_group.dart';
import 'package:oh_my_mc/ui/components/app_slider.dart';
import 'package:oh_my_mc/ui/components/app_switch.dart';
import 'package:oh_my_mc/ui/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  m3.MaterialApp(
    theme: AppTheme.material(Brightness.light),
    home: m3.Scaffold(body: m3.Center(child: child)),
  ),
);

/// The semantics node of the innermost `Semantics` above [finder].
String? _labelOf(WidgetTester tester, Finder finder) {
  final semantics = tester.getSemantics(finder);
  return semantics.label.isEmpty ? null : semantics.label;
}

void main() {
  group('AppSwitch', () {
    testWidgets('announces its label and state, not just a bare toggle', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        AppSwitch(value: true, onChanged: (_) {}, label: 'Animations'),
      );

      final node = tester.getSemantics(find.byType(AppSwitch));
      expect(node.label, 'Animations');
      // The label must join the switch's own node: a label on a node *above* a
      // child the switch excluded would read correctly and be unactivatable.
      final flags = node.getSemanticsData().flagsCollection;
      expect(flags.isToggled, Tristate.isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('without a label it adds no semantics of its own', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, AppSwitch(value: false, onChanged: (_) {}));

      // The switch still exposes itself as a toggle, but carries no invented text.
      expect(_labelOf(tester, find.byType(AppSwitch)), isNull);
      handle.dispose();
    });

    testWidgets('a null onChanged disables the switch', (tester) async {
      await _pump(tester, const AppSwitch(value: false, onChanged: null));

      expect(
        tester.widget<m3.Switch>(find.byType(m3.Switch)).onChanged,
        isNull,
      );
    });
  });

  group('AppSlider', () {
    testWidgets('carries the control name the SDK slider cannot', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        AppSlider(
          value: 2048,
          min: 512,
          max: 8192,
          onChanged: (_) {},
          label: 'Memory',
          valueLabel: '2 GiB',
        ),
      );

      expect(_labelOf(tester, find.byType(AppSlider)), 'Memory');
      handle.dispose();
    });

    testWidgets('passes divisions and the value label through', (tester) async {
      await _pump(
        tester,
        AppSlider(
          value: 2048,
          min: 512,
          max: 8192,
          divisions: 15,
          onChanged: (_) {},
          valueLabel: '2 GiB',
        ),
      );

      final slider = tester.widget<m3.Slider>(find.byType(m3.Slider));
      expect(slider.divisions, 15);
      expect(slider.label, '2 GiB');
    });
  });

  group('AppRadioGroup', () {
    testWidgets('reports the tapped option and keys each row', (tester) async {
      String? picked;
      await _pump(
        tester,
        AppRadioGroup<String>(
          value: 'a',
          options: const {'a': 'Alpha', 'b': 'Beta'},
          onChanged: (value) => picked = value,
          keyPrefix: 'opt',
        ),
      );

      expect(find.byKey(const ValueKey('opt-a')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('opt-b')));
      await tester.pump();
      expect(picked, 'b');
    });

    testWidgets('builds no ListTile, so a decorated card cannot hide its ink', (
      tester,
    ) async {
      // The reason this component exists: `RadioListTile` asserts when it sits
      // under a `DecoratedBox` with a background, which the setup panel is.
      await _pump(
        tester,
        m3.DecoratedBox(
          decoration: const m3.BoxDecoration(color: m3.Color(0xFFEEEEEE)),
          child: AppRadioGroup<String>(
            value: 'a',
            options: const {'a': 'Alpha'},
            onChanged: (_) {},
            keyPrefix: 'opt',
          ),
        ),
      );

      expect(find.byType(m3.RadioListTile<String>), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('AppDialog', () {
    testWidgets('the visible title is also the spoken name', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const AppDialog(
          title: 'Delete instance',
          content: m3.Text('Files go too.'),
        ),
      );

      expect(find.text('Delete instance'), findsOneWidget);
      // The dialog gets the heading as its own label rather than a second,
      // separately-maintained string that could drift from it.
      expect(
        tester
            .widget<m3.AlertDialog>(find.byType(m3.AlertDialog))
            .semanticLabel,
        'Delete instance',
      );
      expect(find.bySemanticsLabel('Delete instance'), findsWidgets);
      handle.dispose();
    });
  });

  group('AppTheme.status', () {
    testWidgets('success stays green under a yellow accent', (tester) async {
      // The whole point of not seeding these: "installed" must not turn yellow
      // just because the user picked a yellow accent.
      late m3.Color success;
      await tester.pumpWidget(
        m3.MaterialApp(
          theme: m3.ThemeData(
            useMaterial3: true,
            colorScheme: m3.ColorScheme.fromSeed(
              seedColor: const m3.Color(0xFFFFC107),
            ),
          ),
          home: m3.Builder(
            builder: (context) {
              success = AppTheme.status(context).success;
              return const m3.SizedBox();
            },
          ),
        ),
      );

      expect(success.g, greaterThan(success.r));
      expect(success.g, greaterThan(success.b));
    });

    testWidgets('danger follows the scheme error colour', (tester) async {
      late m3.Color danger;
      late m3.Color error;
      await tester.pumpWidget(
        m3.MaterialApp(
          theme: AppTheme.material(Brightness.dark),
          home: m3.Builder(
            builder: (context) {
              danger = AppTheme.status(context).danger;
              error = m3.Theme.of(context).colorScheme.error;
              return const m3.SizedBox();
            },
          ),
        ),
      );

      expect(danger, error);
    });
  });
}
