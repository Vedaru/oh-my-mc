import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/app/router.dart';
import 'package:oh_my_mc/data/instance_store.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:oh_my_mc/main.dart';
import 'package:path/path.dart' as p;

/// The language preference must be a door that swings both ways.
///
/// This test mounts the whole app on purpose. Every other UI test goes through a
/// harness that pins `MaterialApp.locale` to English, which is fine for the screens but
/// means the one piece of code that turns a preference into a locale - `AppRoot` - was
/// never exercised by the value it reads.
void main() {
  late Directory data;

  setUp(() async => data = await Directory.systemTemp.createTemp('lang'));
  tearDown(() async {
    if (data.existsSync()) await data.delete(recursive: true);
  });

  Future<MemorySettingsStore> pump(
    WidgetTester tester,
    LanguagePreference language,
  ) async {
    final store = MemorySettingsStore(AppSettings(language: language));
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      OhMyMcApp(
        store: store,
        instanceStore: MemoryInstanceStore(),
        paths: LauncherPaths(
          data: data,
          game: Directory(p.join(data.path, 'minecraft')),
        ),
        initialLocation: Routes.setup,
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('Chinese → English → Chinese', (tester) async {
    final store = await pump(tester, LanguagePreference.chinese);
    expect(find.text('设置'), findsWidgets, reason: 'starts in Chinese');

    await tester.tap(
      find.byKey(const ValueKey('language-LanguagePreference.english')),
    );
    await tester.pumpAndSettle();
    expect(store.current.language, LanguagePreference.english);
    expect(find.text('Setup'), findsWidgets);
    expect(find.text('设置'), findsNothing);

    // Back to Chinese: this is the direction that used to stick.
    await tester.tap(
      find.byKey(const ValueKey('language-LanguagePreference.chinese')),
    );
    await tester.pumpAndSettle();
    expect(store.current.language, LanguagePreference.chinese);
    expect(find.text('设置'), findsWidgets);
    expect(find.text('Setup'), findsNothing);
  });

  testWidgets('English → follow system → back again', (tester) async {
    final store = await pump(tester, LanguagePreference.english);
    expect(find.text('Setup'), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey('language-LanguagePreference.system')),
    );
    await tester.pumpAndSettle();
    expect(store.current.language, LanguagePreference.system);

    // The test platform reports en_US, so "system" renders English here; what must
    // hold is that the preference moved and the app rebuilt from it, not that the
    // text changed on this machine.
    expect(find.text('Setup'), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey('language-LanguagePreference.chinese')),
    );
    await tester.pumpAndSettle();
    expect(store.current.language, LanguagePreference.chinese);
    expect(find.text('设置'), findsWidgets);
  });
}
