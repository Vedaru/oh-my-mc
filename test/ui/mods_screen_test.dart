import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/core/mods/mod_scanner.dart';
import 'package:oh_my_mc/data/instance_providers.dart';
import 'package:oh_my_mc/data/instance_store.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/data/mods_providers.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:oh_my_mc/app/providers.dart';
import 'package:oh_my_mc/ui/instances/instance_mods_screen.dart';
import 'package:path/path.dart' as p;

import '../support/harness.dart';

/// The mod manager, asserted through what it asks the repository to do.
///
/// The file operations themselves are covered in test/core/mod_scanner_test.dart;
/// here the questions are "does the row show the mod's own name", "does the switch
/// call the right thing with the right argument" and "does deleting ask first".
class _FakeMods implements ModsRepository {
  _FakeMods(this.mods);

  final List<ModEntry> mods;
  final enabled = <(String, bool)>[];
  final deleted = <String>[];

  @override
  Future<List<ModEntry>> scan(String directory) async => mods;

  @override
  Future<String> setEnabled(ModEntry mod, bool enabled) async {
    this.enabled.add((mod.fileName, enabled));
    final index = mods.indexWhere((m) => m.path == mod.path);
    if (index >= 0) {
      mods[index] = ModEntry(
        path: mods[index].path,
        enabled: enabled,
        sizeBytes: mods[index].sizeBytes,
        loader: mods[index].loader,
        id: mods[index].id,
        name: mods[index].name,
        version: mods[index].version,
      );
    }
    return mod.path;
  }

  @override
  Future<void> delete(ModEntry mod) async => deleted.add(mod.fileName);
}

ModEntry mod(
  String file, {
  String? id,
  String? name,
  String? version,
  ModLoaderKind loader = ModLoaderKind.fabric,
  bool enabled = true,
  String? problem,
}) => ModEntry(
  path: '/g/mods/$file',
  enabled: enabled,
  sizeBytes: 2048,
  loader: loader,
  id: id ?? name?.toLowerCase(),
  name: name,
  version: version,
  problem: problem,
);

void main() {
  Future<(_FakeMods, ProviderContainer)> pump(
    WidgetTester tester, {
    List<ModEntry> mods = const [],
    List<Instance>? instances,
    VoidCallback? onClose,
  }) async {
    final data = await tester.runAsync(
      () => Directory.systemTemp.createTemp('mods_screen_test'),
    );
    addTearDown(() async {
      if (await data!.exists()) await data.delete(recursive: true);
    });

    final fake = _FakeMods([...mods]);
    final container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWith(
          (ref) => MemorySettingsStore(AppSettings.defaults),
        ),
        instanceStoreProvider.overrideWith(
          (ref) => MemoryInstanceStore(
            instances ??
                [Instance(id: 'demo', name: 'Demo', versionId: '1.20.1')],
          ),
        ),
        launcherPathsProvider.overrideWithValue(
          LauncherPaths(
            data: data!,
            game: Directory(p.join(data.path, 'game')),
          ),
        ),
        modsRepositoryProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpScreen(
      tester,
      container,
      InstanceModsScreen(id: 'demo', onClose: onClose),
    );
    return (fake, container);
  }

  testWidgets('a mod is listed by its own name, with version and loader', (
    tester,
  ) async {
    await pump(
      tester,
      mods: [
        mod('sodium-0.5.11.jar', name: 'Sodium', version: '0.5.11'),
        mod(
          'jei-15.jar',
          name: 'Just Enough Items',
          version: '15.2.0',
          loader: ModLoaderKind.forge,
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Sodium'), findsOneWidget);
    expect(find.textContaining('0.5.11 · Fabric'), findsOneWidget);
    expect(find.textContaining('15.2.0 · Forge'), findsOneWidget);
  });

  testWidgets('a disabled mod says so and its switch is off', (tester) async {
    final (_, container) = await pump(
      tester,
      mods: [mod('sodium.jar', name: 'Sodium', enabled: false)],
    );
    await tester.pumpAndSettle();

    expect(find.text('Off'), findsOneWidget);
    expect(
      container.read(instanceModsProvider('demo')).value!.single.enabled,
      isFalse,
    );
  });

  testWidgets('turning a mod off renames it through the repository', (
    tester,
  ) async {
    final fake = (await pump(
      tester,
      mods: [mod('sodium.jar', name: 'Sodium')],
    )).$1;
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mod-switch-sodium.jar')));
    await tester.pumpAndSettle();

    expect(fake.enabled, [('sodium.jar', false)]);
  });

  testWidgets('deleting asks first, and cancelling does nothing', (
    tester,
  ) async {
    final fake = (await pump(
      tester,
      mods: [mod('sodium.jar', name: 'Sodium')],
    )).$1;
    await tester.pumpAndSettle();

    // The trash icon is the row's supplementary action.
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this mod?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fake.deleted, isEmpty);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mod-delete-confirm')));
    await tester.pumpAndSettle();

    expect(fake.deleted, ['sodium.jar']);
  });

  testWidgets('the filter narrows the list by name', (tester) async {
    await pump(
      tester,
      mods: [
        mod('sodium.jar', id: 'sodium', name: 'Sodium'),
        mod(
          'jei.jar',
          id: 'jei',
          name: 'Just Enough Items',
          loader: ModLoaderKind.forge,
        ),
      ],
    );
    await tester.pumpAndSettle();

    // Matched by mod id, not by the file name: the id is what a user knows from
    // the mod page, and the name is what they see in the list.
    await tester.enterText(find.byKey(const ValueKey('mods-filter')), 'jei');
    await tester.pumpAndSettle();

    expect(find.text('Just Enough Items'), findsOneWidget);
    expect(find.text('Sodium'), findsNothing);
  });

  testWidgets('a jar that is not a mod is shown with the reason', (
    tester,
  ) async {
    await pump(
      tester,
      mods: [mod('oops.jar', problem: 'not a jar (no zip signature)')],
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('no zip signature'), findsOneWidget);
  });

  testWidgets('no mods reads as empty rather than as an error', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('No mods yet'), findsOneWidget);
    // One "Get mods", in the header: the empty state no longer repeats it.
    expect(find.text('Get mods'), findsOneWidget);
  });

  testWidgets('a deleted instance is a message, not a crash', (tester) async {
    await pump(tester, instances: const [], mods: const []);
    await tester.pumpAndSettle();

    expect(find.text('This instance no longer exists.'), findsOneWidget);
  });
}
