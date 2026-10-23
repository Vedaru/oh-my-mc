import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/app/router.dart';
import 'package:oh_my_mc/data/instance_store.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:oh_my_mc/main.dart';
import 'package:path/path.dart' as p;

/// The wallpaper is a setting that paints behind every page, under a scrim. These tests
/// pin the three states that matter: set, cleared, and a path that no longer exists.
void main() {
  late Directory data;
  late File picture;

  setUp(() async {
    data = await Directory.systemTemp.createTemp('wallpaper');
    picture = File(p.join(data.path, 'wall.png'));
    // A 1×1 PNG: enough for the decoder, and the shell only needs to be asked to paint.
    await picture.writeAsBytes(const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
      0x42, 0x60, 0x82,
    ]);
  });

  tearDown(() async {
    if (data.existsSync()) await data.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester, String? background) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      OhMyMcApp(
        store: MemorySettingsStore(AppSettings(backgroundPath: background)),
        instanceStore: MemoryInstanceStore(),
        paths: LauncherPaths(
          data: data,
          game: Directory(p.join(data.path, 'minecraft')),
        ),
        initialLocation: Routes.launch,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('a chosen picture is painted behind the shell', (tester) async {
    await pump(tester, picture.path);
    expect(find.byKey(const ValueKey('shell-background')), findsOneWidget);
  });

  testWidgets('no picture means no background layer at all', (tester) async {
    await pump(tester, null);
    expect(find.byKey(const ValueKey('shell-background')), findsNothing);
  });

  testWidgets('a path that no longer exists does not blank the window', (
    tester,
  ) async {
    await pump(tester, p.join(data.path, 'gone.png'));
    // The layer is there (the setting is set) but the image fails into nothing, and the
    // page still draws: a moved file must not leave an empty launcher.
    expect(find.byKey(const ValueKey('shell-background')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
