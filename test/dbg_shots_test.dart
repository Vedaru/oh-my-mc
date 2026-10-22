@Tags(['shots'])
library;

import 'dart:io';

import 'package:material_ui/material_ui.dart' as m3;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/data/instance_store.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:oh_my_mc/main.dart';
import 'package:path/path.dart' as p;

Future<void> _loadFonts() async {
  for (final entry in {
    'Roboto': '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    'Segoe UI': '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  }.entries) {
    final bytes = File(entry.value).readAsBytesSync();
    final loader = FontLoader(entry.key)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}

Instance _instance(String id, String name, String version, {DateTime? last}) =>
    Instance(
      id: id,
      name: name,
      versionId: version,
      createdAt: DateTime(2026, 1, 1),
      lastPlayedAt: last,
      totalPlaytime: const Duration(hours: 12, minutes: 30),
    );

void main() {
  setUpAll(_loadFonts);

  Future<void> shoot(
    WidgetTester tester,
    String route,
    String file, {
    List<Instance> instances = const [],
    AppSettings settings = AppSettings.defaults,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final data = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('shot'),
    ))!;
    addTearDown(() async {
      if (await data.exists()) await data.delete(recursive: true);
    });

    await tester.pumpWidget(
      OhMyMcApp(
        store: MemorySettingsStore(settings),
        instanceStore: MemoryInstanceStore(instances),
        paths: LauncherPaths(
          data: data,
          game: Directory(p.join(data.path, 'minecraft')),
        ),
        initialLocation: route,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    await expectLater(
      find.byType(m3.MaterialApp),
      matchesGoldenFile('shots/$file.png'),
    );
  }

  testWidgets('launch', (tester) async {
    await shoot(
      tester,
      '/launch',
      'launch',
      instances: [
        _instance(
          'survival',
          'Survival',
          '1.20.1',
          last: DateTime(2026, 10, 20),
        ),
      ],
    );
  });

  testWidgets('instances', (tester) async {
    await shoot(
      tester,
      '/instances',
      'instances',
      instances: [
        _instance('a', 'Survival', '1.20.1', last: DateTime(2026, 10, 20)),
        _instance('b', 'Creative', '26.3'),
        _instance('c', 'Modded', '1.19.2'),
      ],
    );
  });

  testWidgets('instances empty', (tester) async {
    await shoot(tester, '/instances', 'instances-empty');
  });

  testWidgets('detail', (tester) async {
    await shoot(
      tester,
      '/instances/a',
      'detail',
      instances: [_instance('a', 'Survival', '1.20.1')],
    );
  });

  testWidgets('download', (tester) async {
    await shoot(tester, '/download', 'download');
  });

  testWidgets('setup', (tester) async {
    await shoot(tester, '/setup', 'setup');
  });

  testWidgets('logs', (tester) async {
    await shoot(tester, '/logs', 'logs');
  });

  testWidgets('app root', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('shot2'),
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
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
  });
}
