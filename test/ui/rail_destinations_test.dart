import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/app/router.dart';
import 'package:oh_my_mc/data/instance_store.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:oh_my_mc/main.dart';
import 'package:path/path.dart' as p;

/// The rail is the app's table of contents: every top-level thing a session needs is one
/// click away, in the order a session uses them. These tests pin *which* destinations
/// exist and that a child route still highlights its parent.
void main() {
  late Directory data;

  setUp(() async {
    data = await Directory.systemTemp.createTemp('rail');
  });

  tearDown(() async {
    if (data.existsSync()) await data.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester, String location) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      OhMyMcApp(
        store: MemorySettingsStore(AppSettings()),
        instanceStore: MemoryInstanceStore(),
        paths: LauncherPaths(
          data: data,
          game: Directory(p.join(data.path, 'minecraft')),
        ),
        initialLocation: location,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('every destination is in the rail, and there are seven', (
    tester,
  ) async {
    await pump(tester, Routes.launch);
    final rail = tester.widget<m3.NavigationRail>(
      find.byType(m3.NavigationRail),
    );
    expect(rail.destinations, hasLength(7));
    expect(rail.destinations.map((d) => ((d.label as m3.Text).data)).toList(), [
      'Launch',
      'Instances',
      'Accounts',
      'Multiplayer',
      'Download',
      'Logs',
      'Setup',
    ]);
  });

  testWidgets(
    'a destination selects itself, and a child route selects it too',
    (tester) async {
      for (final location in [
        Routes.accounts,
        Routes.network,
        Routes.setup,
        // A child route keeps its parent highlighted: `/instances/<id>` is Instances.
        '${Routes.instances}/abc',
      ]) {
        await pump(tester, location);
        final rail = tester.widget<m3.NavigationRail>(
          find.byType(m3.NavigationRail),
        );
        expect(
          rail.selectedIndex,
          rail.destinations.indexWhere(
            (d) => (d.label as m3.Text).data == _labelFor(location),
          ),
          reason: '$location highlighted the wrong destination',
        );
      }
    },
  );
}

String _labelFor(String location) => switch (location) {
  _ when location.startsWith('/accounts') => 'Accounts',
  _ when location.startsWith('/network') => 'Multiplayer',
  _ when location.startsWith('/setup') => 'Setup',
  _ when location.startsWith('/instances') => 'Instances',
  _ => 'Launch',
};
