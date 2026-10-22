import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/app/providers.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/core/mc/host.dart';
import 'package:oh_my_mc/core/mc/java_manager.dart';
import 'package:oh_my_mc/data/instance_providers.dart';
import 'package:oh_my_mc/data/instance_store.dart';
import 'package:oh_my_mc/data/java_providers.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:oh_my_mc/ui/instances/instance_detail_screen.dart';
import 'package:oh_my_mc/ui/components/app_button.dart';

import '../support/harness.dart';

import 'package:path/path.dart' as p;

/// The detail page, asserted through the store rather than through the widgets.
///
/// Every field here is a *write*: the page saves as you type, so the assertion
/// that matters is "the store now holds the edited value", not "a text box
/// contains text".
void main() {
  Instance sample({
    String id = 'demo',
    String name = 'Demo',
    String versionId = '1.20.1',
    IsolationKind isolation = IsolationKind.shareLibraries,
    int? memoryMb,
    String? javaPath,
  }) => Instance(
    id: id,
    name: name,
    versionId: versionId,
    isolation: isolation,
    memoryMb: memoryMb,
    javaPath: javaPath,
  );

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    List<Instance> instances = const [],
    String id = 'demo',
    AppSettings settings = AppSettings.defaults,
    VoidCallback? onClose,
    Future<JavaRuntime?> Function(String)? probe,
  }) async {
    // A real temp directory, because the page reads the game path from
    // `launcherPathsProvider` and a missing override is a hard error.
    final data = await tester.runAsync(
      () => Directory.systemTemp.createTemp('instance_detail_test'),
    );
    addTearDown(() async {
      if (await data!.exists()) await data.delete(recursive: true);
    });

    final container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWith(
          (ref) => MemorySettingsStore(settings),
        ),
        instanceStoreProvider.overrideWith(
          (ref) => MemoryInstanceStore(instances),
        ),
        launcherPathsProvider.overrideWithValue(
          LauncherPaths(
            data: data!,
            game: Directory(p.join(data.path, 'game')),
          ),
        ),
        // No real JVM is probed in a widget test.
        javaRuntimesProvider.overrideWith(() => _EmptyRuntimes()),
        javaProbeRunnerProvider.overrideWithValue(probe ?? (exe) async => null),
      ],
    );
    addTearDown(container.dispose);

    // The page is a lazily built ListView: a section that is off screen does not
    // exist to `find`, so a taller surface beats teaching every test to scroll.
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpScreen(
      tester,
      container,
      InstanceDetailScreen(id: id, onClose: onClose),
    );
    return container;
  }

  Instance stored(ProviderContainer container, [String id = 'demo']) =>
      (container.read(instanceListProvider) as InstanceListReady).instances
          .firstWhere((i) => i.id == id);

  group('instance detail', () {
    testWidgets('shows the instance it was asked for, not the selected one', (
      tester,
    ) async {
      await pump(
        tester,
        instances: [
          sample(id: 'a', name: 'Alpha'),
          sample(id: 'b', name: 'Beta'),
        ],
        id: 'b',
      );

      // Twice: the page title and the name field.
      expect(find.text('Beta'), findsNWidgets(2));
      expect(find.text('Alpha'), findsNothing);
    });

    testWidgets('a deleted instance says so instead of throwing', (
      tester,
    ) async {
      await pump(tester, instances: [sample()], id: 'gone');

      expect(find.text('This instance no longer exists.'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
    });

    testWidgets('renaming writes the new name to the store', (tester) async {
      final container = await pump(tester, instances: [sample()]);

      final field = find.byKey(const ValueKey('instance-name'));
      await tester.enterText(field, 'Renamed');
      // Committed on submit, not per keystroke: one whole-file write per edit.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(stored(container).name, 'Renamed');
    });

    testWidgets('the isolation switch persists', (tester) async {
      final container = await pump(tester, instances: [sample()]);

      await tester.tap(find.byKey(const ValueKey('instance-isolation')));
      await tester.pumpAndSettle();

      expect(stored(container).isolation, IsolationKind.isolated);
    });

    testWidgets('the Java test button reports a working runtime', (
      tester,
    ) async {
      await pump(
        tester,
        instances: [sample(javaPath: '/opt/jdk17/bin/java')],
        probe: (exe) async => JavaRuntime(
          path: exe,
          majorVersion: 17,
          versionString: '17.0.9',
          vendor: 'Eclipse Adoptium',
          arch: HostArch.x86_64,
        ),
      );

      expect(
        find.textContaining('Runs this file'),
        findsOneWidget,
        reason: 'the button needs to say what it does before it is pressed',
      );

      await tester.tap(find.byKey(const ValueKey('instance-java-test')));
      await tester.pumpAndSettle();

      expect(
        find.text('Works: Java 17, 17.0.9, Eclipse Adoptium'),
        findsOneWidget,
      );
    });

    testWidgets('the Java test reports a file that is not a runtime', (
      tester,
    ) async {
      await pump(
        tester,
        instances: [sample(javaPath: '/opt/nope/bin/java')],
        probe: (exe) async => null,
      );

      await tester.tap(find.byKey(const ValueKey('instance-java-test')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('did not answer as a Java runtime'),
        findsOneWidget,
      );
    });

    testWidgets('no test button without a chosen runtime', (tester) async {
      await pump(tester, instances: [sample()]);

      // Nothing to run: "Automatic" is a decision the version makes at launch.
      expect(find.byKey(const ValueKey('instance-java-test')), findsNothing);
    });

    testWidgets('switching to isolated warns that nothing is migrated', (
      tester,
    ) async {
      await pump(tester, instances: [sample()]);

      // Nothing moves. If this message disappears, the switch starts looking like
      // a data migration and users will lose track of their worlds.
      expect(
        find.byKey(const ValueKey('instance-isolation-empty')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('instance-isolation')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('instance-isolation-empty')),
        findsOneWidget,
      );
      expect(find.textContaining('stay there'), findsOneWidget);
    });

    testWidgets('switching back to shared withdraws the warning', (
      tester,
    ) async {
      await pump(
        tester,
        instances: [sample(isolation: IsolationKind.isolated)],
      );

      await tester.tap(find.byKey(const ValueKey('instance-isolation')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('instance-isolation-empty')),
        findsNothing,
      );
    });

    testWidgets('the memory override starts off and writes a value when on', (
      tester,
    ) async {
      final container = await pump(
        tester,
        instances: [sample()],
        settings: const AppSettings(memoryMb: 4096),
      );

      // Off means "use the global default", which is a separate state from
      // "4096", so the switch must write the global value on enable.
      expect(find.text('Using the default (4096 MB)'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('instance-memory-override')));
      await tester.pumpAndSettle();

      expect(stored(container).memoryMb, 4096);
    });

    testWidgets('turning the override back off clears it', (tester) async {
      final container = await pump(tester, instances: [sample(memoryMb: 8192)]);

      await tester.tap(find.byKey(const ValueKey('instance-memory-override')));
      await tester.pumpAndSettle();

      expect(
        stored(container).memoryMb,
        isNull,
        reason: 'clearing must not leave the old number behind',
      );
    });

    testWidgets('JVM arguments are parsed and stored as argv', (tester) async {
      final container = await pump(tester, instances: [sample()]);

      await tester.enterText(
        find.byKey(const ValueKey('instance-jvm-args')),
        '-Dfoo="a b"\n-XX:+UseG1GC',
      );
      await tester.pumpAndSettle();

      // The write is on blur: a per-keystroke save would rewrite the whole
      // instances file for every character typed.
      expect(stored(container).jvmArgs, isEmpty);
      expect(find.textContaining('2 arguments'), findsOneWidget);

      // Unfocus the field to commit.
      await tester.tap(find.byKey(const ValueKey('instance-name')));
      await tester.pumpAndSettle();

      expect(stored(container).jvmArgs, ['-Dfoo=a b', '-XX:+UseG1GC']);
    });

    testWidgets('game arguments land in their own field', (tester) async {
      final container = await pump(tester, instances: [sample()]);

      await tester.enterText(
        find.byKey(const ValueKey('instance-game-args')),
        '--fullscreen',
      );
      await tester.tap(find.byKey(const ValueKey('instance-name')));
      await tester.pumpAndSettle();

      expect(stored(container).gameArgs, ['--fullscreen']);
      expect(
        stored(container).jvmArgs,
        isEmpty,
        reason: 'the two editors must not write the same field',
      );
    });

    testWidgets('existing arguments load into the editor', (tester) async {
      await pump(
        tester,
        instances: [
          sample().copyWith(jvmArgs: ['-Xmx4G', '-Dfoo=a b']),
        ],
      );

      // Quoted on the way in, so the round trip back through the parser is the
      // same list rather than three arguments.
      expect(find.text('-Xmx4G\n"-Dfoo=a b"'), findsOneWidget);
    });

    testWidgets('delete asks first, and the instance survives a cancel', (
      tester,
    ) async {
      final container = await pump(tester, instances: [sample()]);

      await tester.tap(find.widgetWithText(AppButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.textContaining('This cannot be undone'), findsOneWidget);

      await tester.tap(find.widgetWithText(AppButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(
        (container.read(instanceListProvider) as InstanceListReady).instances,
        hasLength(1),
      );
    });

    testWidgets('confirming delete removes it and leaves the page', (
      tester,
    ) async {
      var closed = 0;
      final container = await pump(
        tester,
        instances: [sample()],
        onClose: () => closed++,
      );

      await tester.tap(find.widgetWithText(AppButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('instance-delete-confirm')));
      // The confirmed delete touches the real filesystem, and `Directory.exists`
      // is a real future that never resolves inside the fake-async zone a widget
      // test runs in. Let it run for real, then pump.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(
        (container.read(instanceListProvider) as InstanceListReady).instances,
        isEmpty,
      );
      // Staying on a page for an instance that no longer exists would show the
      // "no longer exists" fallback, which reads like an error.
      expect(closed, 1);
    });
  });
}

/// The runtimes list, answered without touching the disk.
class _EmptyRuntimes extends JavaRuntimesController {
  @override
  Future<List<ManagedJavaRuntime>> build() async => const [];
}
