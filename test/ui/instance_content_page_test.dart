import 'dart:io';

import 'package:flutter/widgets.dart' show Size, ValueKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/app/providers.dart';
import 'package:oh_my_mc/core/game/content.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/core/mods/mod_scanner.dart';
import 'package:oh_my_mc/data/game_content_provider.dart';
import 'package:oh_my_mc/data/instance_providers.dart';
import 'package:oh_my_mc/data/instance_store.dart';
import 'package:oh_my_mc/core/server/server_ping.dart';
import 'package:oh_my_mc/data/mods_providers.dart';
import 'package:oh_my_mc/data/server_providers.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:oh_my_mc/ui/components/app_button.dart';
import 'package:oh_my_mc/ui/instances/instance_detail_screen.dart';

import 'package:oh_my_mc/ui/motion/motion.dart';

import '../support/harness.dart';

/// The instance page is a section list with **one content kind per section** (mods,
/// resource packs, shaders, worlds, servers, data packs), the way Prism and PCL arrange
/// a version. These tests pin the arrangement and the verbs: a resource pack toggles
/// through `options.txt`, a world only deletes, and a data pack needs a world first.
class _Ready extends InstanceListNotifier {
  _Ready(this.instance);

  final Instance instance;

  @override
  InstanceListState build() =>
      InstanceListReady([instance], selectedId: instance.id);
}

class _FakeContent extends GameContent {
  _FakeContent(super.root, this.byKind);

  final Map<ContentKind, List<ContentEntry>> byKind;
  final writes = <String>[];

  @override
  Future<List<ContentEntry>> list(ContentKind kind) async =>
      byKind[kind] ?? const [];

  @override
  Future<List<String>> setResourcePackEnabled(String name, bool enabled) async {
    writes.add('pack:$name=$enabled');
    return const [];
  }

  @override
  Future<void> addServer({required String name, required String ip}) async {
    writes.add('server:$name@$ip');
  }

  @override
  Future<void> delete(ContentKind kind, String path) async {
    writes.add('delete:$path');
    byKind[kind] = [
      for (final entry in byKind[kind] ?? const <ContentEntry>[])
        if (entry.path != path) entry,
    ];
  }
}

void main() {
  const instance = Instance(
    id: 'demo',
    name: 'Demo',
    versionId: '1.20.1',
    isolation: IsolationKind.isolated,
  );

  late _FakeContent content;
  // Overridden per test below; the default pings nothing.

  ContentEntry entry(String name, {bool enabled = false, String? detail}) =>
      ContentEntry(
        name: name,
        path: '/$name',
        isDirectory: false,
        sizeBytes: 2048,
        enabled: enabled,
        detail: detail,
      );

  setUp(() {
    content = _FakeContent('/root', {
      ContentKind.resourcePacks: [
        entry('Pack A.zip', enabled: true),
        entry('Pack B.zip'),
      ],
      ContentKind.shaderPacks: [entry('BSL.zip')],
      ContentKind.saves: [entry('World', detail: '2 h ago')],
      ContentKind.servers: const [],
      ContentKind.datapacks: [entry('Terralith.zip')],
    });
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    String section = 'overview',
    List<Override> overrides = const [],
  }) async {
    final container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWith(
          (ref) => MemorySettingsStore(AppSettings.defaults),
        ),
        instanceStoreProvider.overrideWith(
          (ref) => MemoryInstanceStore(const [instance]),
        ),
        instanceListProvider.overrideWith(() => _Ready(instance)),
        launcherPathsProvider.overrideWithValue(
          LauncherPaths(
            data: Directory('/data'),
            game: Directory('/data/game'),
          ),
        ),
        gameContentProvider.overrideWith(
          (ref) =>
              (root) => content,
        ),
        instanceModsProvider.overrideWith(
          (ref, id) async => const <ModEntry>[],
        ),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpScreen(
      tester,
      container,
      const InstanceDetailScreen(id: 'demo'),
      motion: Motion.none,
    );
    if (section != 'overview') {
      await tester.tap(find.byKey(ValueKey('detail-section-$section')));
      await tester.pumpAndSettle();
    }
    return container;
  }

  testWidgets('each content kind is its own section, not one filtered list', (
    tester,
  ) async {
    await pump(tester);

    // Eight doors: the sections Prism's instance window has, minus the ones that do
    // not exist here (notes, screenshots, texture packs).
    for (final section in [
      'overview',
      'mods',
      'resource-packs',
      'shader-packs',
      'worlds',
      'servers',
      'data-packs',
      'settings',
    ]) {
      expect(
        find.byKey(ValueKey('detail-section-$section')),
        findsOneWidget,
        reason: 'missing section $section',
      );
    }
  });

  testWidgets('the resource pack section lists packs and toggles options.txt', (
    tester,
  ) async {
    await pump(tester, section: 'resource-packs');

    expect(find.text('Pack A.zip'), findsOneWidget);
    expect(find.text('Pack B.zip'), findsOneWidget);
    expect(
      tester.widgetList<m3.Switch>(find.byType(m3.Switch)).map((s) => s.value),
      [true, false],
    );

    await tester.tap(find.byType(m3.Switch).last);
    await tester.pumpAndSettle();

    expect(content.writes, ['pack:Pack B.zip=true']);
  });

  testWidgets('the shader section has no switch: the game owns that state', (
    tester,
  ) async {
    await pump(tester, section: 'shader-packs');

    expect(find.text('BSL.zip'), findsOneWidget);
    expect(find.byType(m3.Switch), findsNothing);
  });

  testWidgets('a world is deleted only after a confirmation', (tester) async {
    await pump(tester, section: 'worlds');

    await tester.tap(find.byKey(const m3.ValueKey('content-World')));
    await tester.pumpAndSettle();
    // The row is a list entry, not a button: delete is the trailing icon.
    expect(content.writes, isEmpty);

    await tester.tap(find.byIcon(m3.Icons.delete));
    await tester.pumpAndSettle();
    expect(find.textContaining('This cannot be undone'), findsOneWidget);

    await tester.tap(find.byKey(const m3.ValueKey('content-confirm-delete')));
    await tester.pumpAndSettle();
    expect(content.writes, ['delete:/World']);
  });

  testWidgets('a data pack section starts from a world', (tester) async {
    await pump(tester, section: 'data-packs');

    // The picker names the world, and the packs listed are that world's.
    expect(find.text('Which world?'), findsOneWidget);
    expect(find.text('World'), findsWidgets);
    expect(find.text('Terralith.zip'), findsOneWidget);
  });

  testWidgets('mods and packs do not share a list', (tester) async {
    await pump(tester, section: 'resource-packs');
    expect(find.text('Terralith.zip'), findsNothing);
    expect(find.text('World'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('detail-section-data-packs')));
    await tester.pumpAndSettle();
    // The pack from the previous section is gone: switching sections switches lists.
    expect(find.text('Pack A.zip'), findsNothing);
    expect(find.text('Terralith.zip'), findsOneWidget);
  });

  testWidgets('a server row shows whether the server is up', (tester) async {
    content.byKind[ContentKind.servers] = [
      ContentEntry(
        name: 'SMP',
        path: 'mc.example.net:25565',
        isDirectory: false,
      ),
    ];
    await pump(
      tester,
      section: 'servers',
      overrides: [
        serverPingerProvider.overrideWithValue(
          (address) async => const ServerPing.ok(
            ServerStatus(
              motd: 'A Quiet Place',
              online: 7,
              max: 20,
              latencyMs: 42,
            ),
          ),
        ),
      ],
    );

    // The row answers "is it up" before the user reads anything else.
    expect(find.textContaining('A Quiet Place'), findsOneWidget);
    expect(find.textContaining('7/20'), findsOneWidget);
    expect(find.textContaining('42 ms'), findsOneWidget);
  });

  testWidgets('a server that does not answer says so, on its own row', (
    tester,
  ) async {
    content.byKind[ContentKind.servers] = [
      ContentEntry(name: 'Dead', path: '10.0.0.1:25565', isDirectory: false),
    ];
    await pump(
      tester,
      section: 'servers',
      overrides: [
        serverPingerProvider.overrideWithValue(
          (address) async => const ServerPing.failed('timed out'),
        ),
      ],
    );

    expect(find.textContaining('timed out'), findsOneWidget);
  });

  testWidgets('a server is added as a name and an address, not a download', (
    tester,
  ) async {
    await pump(tester, section: 'servers');

    await tester.tap(find.byKey(const ValueKey('content-add-server')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('server-name')), 'SMP');
    await tester.enterText(
      find.byKey(const ValueKey('server-address')),
      'mc.example.net:25565',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(content.writes, ['server:SMP@mc.example.net:25565']);
  });

  testWidgets('the mods deep link opens the mods section', (tester) async {
    final container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWith(
          (ref) => MemorySettingsStore(AppSettings.defaults),
        ),
        instanceStoreProvider.overrideWith(
          (ref) => MemoryInstanceStore(const [instance]),
        ),
        instanceListProvider.overrideWith(() => _Ready(instance)),
        launcherPathsProvider.overrideWithValue(
          LauncherPaths(
            data: Directory('/data'),
            game: Directory('/data/game'),
          ),
        ),
        gameContentProvider.overrideWith(
          (ref) =>
              (root) => content,
        ),
        instanceModsProvider.overrideWith(
          (ref, id) async => const <ModEntry>[],
        ),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpScreen(
      tester,
      container,
      const InstanceDetailScreen(id: 'demo', initialSection: 'mods'),
      motion: Motion.none,
    );
    await tester.pumpAndSettle();

    // The mods section is selected, and its install action is there: the section is
    // the page's, not a separate screen's.
    expect(find.byKey(const m3.ValueKey('content-install')), findsOneWidget);
    expect(find.byType(AppButton), findsWidgets);
  });
}
