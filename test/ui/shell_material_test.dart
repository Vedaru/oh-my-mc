import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/data/instance_store.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:oh_my_mc/main.dart';
import 'package:oh_my_mc/ui/instances/instance_detail_screen.dart';
import 'package:path/path.dart' as p;

/// The page must live under a `Material` ancestor.
///
/// This is a bug that ships silently and then looks like a styling disaster: with
/// no `Material` above it, an `InkWell` asserts on first paint and every `Text`
/// that does not pass an explicit style falls back to `MaterialApp`'s debug error
/// style - 48 px, red, yellow double underline. It is not visible in any widget
/// test that only looks for keys or strings, so it is pinned here: the shell is
/// the one place that has to provide the ancestor, and every route is checked.
void main() {
  const materialErrorStyleFontSize = 48.0;
  const routes = ['/launch', '/instances', '/download', '/logs', '/setup'];

  for (final route in routes) {
    testWidgets('$route renders under a Material ancestor', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final data = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('shell'),
      ))!;
      addTearDown(() async {
        if (await data.exists()) await data.delete(recursive: true);
      });

      await tester.pumpWidget(
        OhMyMcApp(
          store: MemorySettingsStore(AppSettings.defaults),
          instanceStore: MemoryInstanceStore(const []),
          paths: LauncherPaths(
            data: data,
            game: Directory(p.join(data.path, 'minecraft')),
          ),
          initialLocation: route,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // An ink splash without a Material throws here, not at first user click.
      expect(tester.takeException(), isNull);

      expect(
        find.byType(m3.Material),
        findsWidgets,
        reason: 'the shell must introduce a Material for the page',
      );

      final texts = tester.elementList(find.byType(m3.Text));
      expect(texts, isNotEmpty);
      for (final element in texts) {
        final style = DefaultTextStyle.of(element).style;
        expect(
          style.fontSize,
          isNot(materialErrorStyleFontSize),
          reason:
              'a Text in $route resolved MaterialApp\'s error style, which means '
              'it has no Material ancestor carrying a real DefaultTextStyle',
        );
      }
    });
  }

  testWidgets('/instances/:id renders the detail screen, not the launch '
      'screen', (tester) async {
    // The route parameter is the only thing that distinguishes this page from
    // `/launch`; comparing `state.uri.path` to the pattern left every "Open
    // settings" click rendering the launch screen instead.
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final data = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('detail'),
    ))!;
    addTearDown(() async {
      if (await data.exists()) await data.delete(recursive: true);
    });

    await tester.pumpWidget(
      OhMyMcApp(
        store: MemorySettingsStore(AppSettings.defaults),
        instanceStore: MemoryInstanceStore([
          Instance(
            id: 'survival',
            name: 'Survival',
            versionId: '1.20.1',
            createdAt: DateTime(2026, 1, 1),
          ),
        ]),
        paths: LauncherPaths(
          data: data,
          game: Directory(p.join(data.path, 'minecraft')),
        ),
        initialLocation: '/instances/survival',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.byType(InstanceDetailScreen), findsOneWidget);

    // Drop the page's cached state before the temp dir goes away.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
