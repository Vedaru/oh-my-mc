import 'dart:io';

import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/app/providers.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/core/mods/mod_installer.dart';
import 'package:oh_my_mc/core/mods/modrinth.dart';
import 'package:oh_my_mc/data/instance_providers.dart';
import 'package:oh_my_mc/data/instance_store.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/data/modrinth_providers.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:oh_my_mc/ui/components/action_card.dart';
import 'package:oh_my_mc/ui/download/download_content_bar.dart';
import 'package:path/path.dart' as p;

import '../support/harness.dart';

/// Installs nothing for real: `resolve` answers one plan and the "installer" drops a
/// file. What is being tested is where the file lands and whether a resource pack is
/// switched on afterwards - the parts a user would notice going wrong.
class _FakeClient implements ModrinthClient {
  _FakeClient(this.fileName);

  final String fileName;
  final searches = <({String query, String type})>[];

  @override
  Future<List<ModrinthProject>> search(
    String query, {
    String projectType = 'mod',
    String? gameVersion,
    String? loader,
    int limit = 20,
    dynamic cancel,
  }) async {
    searches.add((query: query, type: projectType));
    return const [
      ModrinthProject(
        id: 'p1',
        slug: 'p',
        title: 'A Pack',
        description: 'desc',
        downloads: 1,
      ),
    ];
  }

  @override
  Future<List<ModInstallPlan>> resolve({
    required String projectId,
    required String title,
    required String gameVersion,
    String? loader,
    String projectType = 'mod',
    dynamic cancel,
    void Function(String projectId)? onProject,
  }) async => [
    ModInstallPlan(
      projectId: projectId,
      title: title,
      file: ModrinthFile(
        url: 'https://example.invalid/$fileName',
        filename: fileName,
        sizeBytes: 1,
      ),
    ),
  ];

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInstaller implements ModInstaller {
  @override
  Future<ModInstallOutcome> install({
    required List<ModInstallPlan> plans,
    required String directory,
    dynamic cancel,
    void Function(int, int, String)? onProgress,
  }) async {
    await Directory(directory).create(recursive: true);
    final names = <String>[];
    for (final plan in plans) {
      await File(p.join(directory, plan.file.filename)).writeAsString('jar');
      names.add(plan.file.filename);
    }
    return ModInstallOutcome(
      installed: names,
      skipped: const [],
      failed: const {},
    );
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory tmp;
  const instance = Instance(
    id: 'demo',
    name: 'Demo',
    versionId: '1.20.1',
    loader: LoaderKind.fabric,
    loaderVersion: '0.16.9',
    isolation: IsolationKind.isolated,
  );

  setUp(() async => tmp = await Directory.systemTemp.createTemp('content-bar'));
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<void> pump(
    WidgetTester tester, {
    List<Instance> instances = const [instance],
    String? selectedId = 'demo',
    _FakeClient? client,
    _FakeInstaller? installer,
  }) async {
    final container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWith(
          (ref) => MemorySettingsStore(AppSettings.defaults),
        ),
        instanceStoreProvider.overrideWith(
          (ref) => MemoryInstanceStore(instances),
        ),
        instanceListProvider.overrideWith(() => _Ready(instances, selectedId)),
        launcherPathsProvider.overrideWithValue(
          LauncherPaths(data: tmp, game: Directory(p.join(tmp.path, 'game'))),
        ),
        if (client != null) modrinthClientProvider.overrideWithValue(client),
        if (installer != null)
          modInstallerProvider.overrideWithValue(installer),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpScreen(tester, container, const DownloadContentBar());
    await tester.pumpAndSettle();
  }

  testWidgets('without a selected instance the catalogues say why', (
    tester,
  ) async {
    await pump(tester, instances: const [], selectedId: null);

    expect(find.textContaining('Select an instance'), findsOneWidget);
    // A card that cannot do anything is disabled, not missing: the page still shows what
    // it can do once an instance exists.
    final card = tester.widget<ActionCard>(
      find.byKey(const m3.ValueKey('catalog-mod')),
    );
    expect(card.onPressed, isNull);
  });

  testWidgets('the five actions are one grid of equal cards', (tester) async {
    await pump(tester);

    const ids = [
      'catalog-mod',
      'catalog-resourcePack',
      'catalog-shader',
      'catalog-datapack',
      'catalog-import-world',
    ];

    // Every one is the same widget, so they cannot drift into "four cards and a link".
    for (final id in ids) {
      expect(find.byKey(m3.ValueKey(id)), findsOneWidget, reason: id);
      expect(
        tester.widget(find.byKey(m3.ValueKey(id))),
        isA<ActionCard>(),
        reason: '$id is not built from the shared card',
      );
    }

    // A grid: the first two share a row and a height, and the wrap puts the third on
    // the same line only when the pane is wide enough.
    final first = tester.getRect(find.byKey(const m3.ValueKey('catalog-mod')));
    final second = tester.getRect(
      find.byKey(const m3.ValueKey('catalog-resourcePack')),
    );
    expect(first.top, moreOrLessEquals(second.top, epsilon: 0.5));
    expect(second.left, greaterThan(first.right));
    expect(first.height, moreOrLessEquals(second.height, epsilon: 0.5));
    expect(first.width, moreOrLessEquals(second.width, epsilon: 0.5));
  });

  testWidgets('a resource pack installs into resourcepacks/ and is enabled', (
    tester,
  ) async {
    final client = _FakeClient('Nice Pack.zip');
    await pump(tester, client: client, installer: _FakeInstaller());

    await tester.tap(find.byKey(const m3.ValueKey('catalog-resourcePack')));
    // Bounded pumps: the dialog autofocuses a field, and a blinking cursor is an
    // animation that never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // The install writes real files (and edits options.txt), and real I/O only runs
    // in `runAsync` - inside the fake clock the future after the first `await` never
    // completes.
    await tester.runAsync(() async {
      await tester.tap(find.text('Install'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The catalogue searched the Modrinth project type, not "mod".
    expect(client.searches.single.type, 'resourcepack');

    final root = p.join(tmp.path, 'instances', 'demo', 'minecraft');
    expect(
      File(p.join(root, 'resourcepacks/Nice Pack.zip')).existsSync(),
      isTrue,
    );
    // Installed *and* on: a pack the user has to enable by hand is a download they
    // still have to finish.
    final options = File(p.join(root, 'options.txt')).readAsStringSync();
    expect(options, contains('file/Nice Pack.zip'));
  });

  testWidgets('a data pack asks which world first', (tester) async {
    // No world exists, so the dialog explains instead of opening a search that has
    // nowhere to install.
    await pump(
      tester,
      client: _FakeClient('x.zip'),
      installer: _FakeInstaller(),
    );

    await tester.tap(find.byKey(const m3.ValueKey('catalog-datapack')));
    // The world lookup is a real directory read: let it finish, then pump frames.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('belongs to a world'), findsOneWidget);
  });
}

/// Mirrors the two states the bar cares about without touching the instance store.
class _Ready extends InstanceListNotifier {
  _Ready(this.instances, this.selectedId);

  final List<Instance> instances;
  final String? selectedId;

  @override
  InstanceListState build() =>
      InstanceListReady(instances, selectedId: selectedId);
}
