import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/data/java_providers.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/l10n/l10n.dart';
import 'package:oh_my_mc/ui/motion/motion.dart';
import 'package:oh_my_mc/ui/setup/setup_screen.dart';
import 'package:path/path.dart' as p;

/// The setup screen's runtime list reads the real filesystem, so these tests use
/// a real temp tree: the point of the screen is what it does with what is
/// actually installed.
void main() {
  late Directory data;

  setUp(() async {
    data = await Directory.systemTemp.createTemp('ommc-setup-');
  });

  tearDown(() async {
    if (await data.exists()) await data.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        launcherPathsProvider.overrideWithValue(
          LauncherPaths(data: data, game: Directory(p.join(data.path, 'game'))),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Real directory IO does not complete under the test binding's fake clock,
    // so the list is resolved first and the widget then reads a ready value.
    await tester.runAsync(() => container.read(javaRuntimesProvider.future));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: FluentApp(
          home: MotionScope(
            motion: Motion.none,
            child: const ScaffoldPage(content: SetupScreen()),
          ),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: appSupportedLocales,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('with nothing downloaded, the list says so', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('java-list-empty')), findsOneWidget);
  });

  testWidgets('a downloaded runtime is listed with its major and disk use', (
    tester,
  ) async {
    final root = Directory(
      p.join(data.path, 'runtimes', 'java-runtime-gamma-17.0.15'),
    );
    File(p.join(root.path, 'bin', 'java'))
      ..createSync(recursive: true)
      ..writeAsStringSync('#!/bin/sh\n');

    await pump(tester);

    expect(find.text('Java 17 (17.0.15)'), findsOneWidget);
    // A freshly-created fake tree is tiny; the assertion is that the size is
    // rendered at all, not a particular number.
    expect(find.textContaining('on disk'), findsOneWidget);
  });
}
