import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/app/router.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/core/update/launcher_update.dart';
import 'package:oh_my_mc/data/instance_store.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:oh_my_mc/data/update_providers.dart';
import 'package:oh_my_mc/main.dart';
import 'package:oh_my_mc/ui/shell/shell_icons.dart';
import 'package:path/path.dart' as p;

/// The launcher's update banner: shown when there is a newer release, gone when the user
/// dismisses it, and absent entirely when the check found nothing.
void main() {
  late Directory data;

  setUp(
    () async => data = await Directory.systemTemp.createTemp('update-banner'),
  );
  tearDown(() async {
    if (data.existsSync()) await data.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester, LauncherUpdate? update) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      OhMyMcApp(
        store: MemorySettingsStore(AppSettings.defaults),
        instanceStore: MemoryInstanceStore(const [
          Instance(id: 'a', name: 'Demo', versionId: '1.20.1'),
        ]),
        paths: LauncherPaths(
          data: data,
          game: Directory(p.join(data.path, 'minecraft')),
        ),
        initialLocation: Routes.launch,
        overrides: [launcherUpdateProvider.overrideWith((ref) async => update)],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('a newer release is announced on the launch page', (
    tester,
  ) async {
    await pump(
      tester,
      const LauncherUpdate(
        version: '0.3.0',
        url: 'https://example.invalid/release',
      ),
    );

    expect(find.byKey(const ValueKey('launcher-update')), findsOneWidget);
    expect(find.textContaining('0.3.0'), findsWidgets);
  });

  testWidgets('no update means no banner', (tester) async {
    await pump(tester, null);
    expect(find.byKey(const ValueKey('launcher-update')), findsNothing);
  });

  testWidgets('the banner can be dismissed', (tester) async {
    await pump(
      tester,
      const LauncherUpdate(
        version: '0.3.0',
        url: 'https://example.invalid/release',
      ),
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('launcher-update')),
        matching: find.byIcon(ShellIcons.close),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('launcher-update')), findsNothing);
  });
}
