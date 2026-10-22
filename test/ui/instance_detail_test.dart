import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/app/providers.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/data/instance_providers.dart';
import 'package:oh_my_mc/data/instance_store.dart';
import 'package:oh_my_mc/data/java_providers.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:oh_my_mc/l10n/l10n.dart';
import 'package:oh_my_mc/ui/instances/instance_detail_screen.dart';
import 'package:oh_my_mc/ui/motion/motion.dart';
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
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: FluentApp(
          theme: FluentThemeData(),
          home: MotionScope(
            motion: Motion.full,
            child: ScaffoldPage(
              content: Padding(
                padding: const EdgeInsets.all(16),
                child: InstanceDetailScreen(id: id, onClose: onClose),
              ),
            ),
          ),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: appSupportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
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

    testWidgets('delete asks first, and the instance survives a cancel', (
      tester,
    ) async {
      final container = await pump(tester, instances: [sample()]);

      await tester.tap(find.widgetWithText(Button, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.textContaining('This cannot be undone'), findsOneWidget);

      await tester.tap(find.widgetWithText(Button, 'Cancel'));
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

      await tester.tap(find.widgetWithText(Button, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('instance-delete-confirm')));
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
