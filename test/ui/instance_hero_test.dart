import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/data/instance_store.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:oh_my_mc/main.dart';
import 'package:oh_my_mc/ui/instances/instance_card.dart';
import 'package:oh_my_mc/ui/instances/instance_detail_screen.dart';
import 'package:oh_my_mc/ui/shell/shell_icons.dart';
import 'package:path/path.dart' as p;

/// The instance icon is a shared element between a card and the detail header.
///
/// A `Hero` only flies when *both* routes are in the navigator for the length of
/// the transition. Opening with `go` rebuilt the stack, so the icon cut to the
/// header while the way back flew - the exact asymmetry these tests pin.
void main() {
  /// Mounts the real app on the grid with one vanilla instance.
  Future<void> pumpGrid(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final data = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('instance_hero'),
    ))!;
    addTearDown(() async {
      if (await data.exists()) await data.delete(recursive: true);
    });

    await tester.pumpWidget(
      OhMyMcApp(
        store: MemorySettingsStore(AppSettings.defaults),
        instanceStore: MemoryInstanceStore(const [
          Instance(id: 'demo', name: 'Demo', versionId: '1.20.1'),
        ]),
        paths: LauncherPaths(
          data: data,
          game: Directory(p.join(data.path, 'minecraft')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(InstanceCard), findsOneWidget);
  }

  /// The icon mid-flight: it lives in the transition's overlay shuttle, so it
  /// belongs to neither endpoint.
  void expectFlying() {
    final icon = find.byIcon(ShellIcons.instance);
    expect(icon, findsOneWidget, reason: 'exactly one icon should be painted');
    expect(
      find.ancestor(of: icon, matching: find.byType(InstanceDetailScreen)),
      findsNothing,
      reason: 'the flying icon is not the header icon yet',
    );
    expect(
      find.ancestor(of: icon, matching: find.byType(InstanceCard)),
      findsNothing,
      reason: 'the flying icon is no longer in the card',
    );
  }

  testWidgets('tapping a card flies its icon up into the header', (
    tester,
  ) async {
    await pumpGrid(tester);

    await tester.tap(find.text('Demo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expectFlying();

    await tester.pumpAndSettle();
    expect(find.byType(InstanceDetailScreen), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byIcon(ShellIcons.instance),
        matching: find.byType(InstanceDetailScreen),
      ),
      findsOneWidget,
      reason: 'the icon has landed in the header',
    );
  });

  testWidgets('leaving the detail page flies it back to the card', (
    tester,
  ) async {
    await pumpGrid(tester);
    await tester.tap(find.text('Demo'));
    await tester.pumpAndSettle();

    // The return control is the drawer's first row: a back arrow in the heading would
    // push the page's mark out of the slot every page's section list lines up on.
    await tester.tap(find.byKey(const ValueKey('section-back')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expectFlying();

    await tester.pumpAndSettle();
    expect(find.byType(InstanceCard), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byIcon(ShellIcons.instance),
        matching: find.byType(InstanceCard),
      ),
      findsOneWidget,
      reason: 'the icon has landed back in the card',
    );
  });
}
