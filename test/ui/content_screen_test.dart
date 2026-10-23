import 'dart:io';

import 'package:flutter/material.dart' show Locale, Size;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/core/game/content.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/data/instance_providers.dart';
import 'package:oh_my_mc/data/instance_store.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/ui/instances/content_screen.dart';
import 'package:path/path.dart' as p;

import '../support/harness.dart';

/// The screens are thin: they list what `GameContent` found and pass writes back to
/// it. What is worth pinning here is the *interaction* - that a toggle reaches the
/// content layer, that a delete asks first, that an add goes through.
///
/// The content layer is faked rather than pointed at a temp directory: real file I/O
/// never completes inside a widget test's fake clock, and
/// `test/core/game/content_test.dart` pins every disk behaviour (options.txt,
/// servers.dat, deletion) against a real tree.
class _ReadyList extends InstanceListNotifier {
  _ReadyList(this.instance);

  final Instance instance;

  @override
  InstanceListState build() =>
      InstanceListReady([instance], selectedId: instance.id);
}

class _FakeContent extends GameContent {
  _FakeContent(super.gameRoot, this.byKind);

  final Map<ContentKind, List<ContentEntry>> byKind;

  /// Every write, in order, so the test can assert what the UI asked for.
  final writes = <String>[];

  @override
  Future<List<ContentEntry>> list(ContentKind kind) async => [
    ...byKind[kind] ?? const <ContentEntry>[],
  ];

  @override
  Future<List<String>> setResourcePackEnabled(String name, bool enabled) async {
    writes.add('pack:$name=$enabled');
    final entries = byKind[ContentKind.resourcePacks] ?? const <ContentEntry>[];
    byKind[ContentKind.resourcePacks] = [
      for (final entry in entries)
        entry.name == name
            ? ContentEntry(
                name: entry.name,
                path: entry.path,
                isDirectory: entry.isDirectory,
                sizeBytes: entry.sizeBytes,
                enabled: enabled,
              )
            : entry,
    ];
    return const [];
  }

  @override
  Future<void> delete(ContentKind kind, String path) async {
    writes.add('delete:$path');
    byKind[kind] = [
      for (final entry in byKind[kind] ?? const <ContentEntry>[])
        if (entry.path != path) entry,
    ];
  }

  @override
  Future<void> addServer({required String name, required String ip}) async {
    writes.add('server:$name@$ip');
    byKind[ContentKind.servers] = [
      ...byKind[ContentKind.servers] ?? const <ContentEntry>[],
      ContentEntry(name: name, path: ip, isDirectory: false, detail: ip),
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

  ContentEntry entry(
    String name, {
    bool enabled = false,
    String? detail,
    int size = 1024,
  }) => ContentEntry(
    name: name,
    path: '/packs/$name',
    isDirectory: false,
    sizeBytes: size,
    enabled: enabled,
    detail: detail,
  );

  setUp(() {
    content = _FakeContent('/game', {
      ContentKind.resourcePacks: [
        entry('Pack A.zip', enabled: true),
        entry('Pack B.zip'),
      ],
      ContentKind.shaderPacks: const [],
      ContentKind.saves: [entry('World', size: 4096)],
      ContentKind.servers: const [],
    });
  });

  Future<void> pump(WidgetTester tester, ContentKind kind) async {
    final container = ProviderContainer(
      overrides: [
        instanceStoreProvider.overrideWith(
          (ref) => MemoryInstanceStore(const [instance]),
        ),
        instanceListProvider.overrideWith(() => _ReadyList(instance)),
        launcherPathsProvider.overrideWithValue(
          LauncherPaths(
            data: Directory(p.join(Directory.systemTemp.path, 'data')),
            game: Directory(p.join(Directory.systemTemp.path, 'game')),
          ),
        ),
        gameContentProvider.overrideWith(
          (ref) =>
              (root) => content,
        ),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpScreen(
      tester,
      container,
      ContentScreen(id: instance.id, kind: kind),
      locale: const Locale('en'),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('resource packs show their state and a toggle writes back', (
    tester,
  ) async {
    await pump(tester, ContentKind.resourcePacks);

    expect(find.text('Pack A.zip'), findsOneWidget);
    expect(find.text('Pack B.zip'), findsOneWidget);
    // Alphabetical: A is on (it is in options.txt), B is off.
    expect(
      tester.widgetList<m3.Switch>(find.byType(m3.Switch)).map((s) => s.value),
      [true, false],
    );

    await tester.tap(find.byType(m3.Switch).last);
    await tester.pumpAndSettle();

    expect(content.writes, ['pack:Pack B.zip=true']);
    // The switch reflects the reload, not just the tap.
    expect(
      tester.widgetList<m3.Switch>(find.byType(m3.Switch)).map((s) => s.value),
      [true, true],
    );
  });

  testWidgets('deleting a world asks first, then deletes', (tester) async {
    await pump(tester, ContentKind.saves);
    expect(find.text('World'), findsOneWidget);

    await tester.tap(find.byKey(const m3.ValueKey('content-delete-World')));
    await tester.pumpAndSettle();
    // The dialog is up and nothing has been deleted yet.
    expect(content.writes, isEmpty);

    await tester.tap(find.byKey(const m3.ValueKey('content-confirm-delete')));
    await tester.pumpAndSettle();

    expect(content.writes, ['delete:/packs/World']);
    expect(find.text('World'), findsNothing);
  });

  testWidgets('a world survives a cancelled delete dialog', (tester) async {
    await pump(tester, ContentKind.saves);

    await tester.tap(find.byKey(const m3.ValueKey('content-delete-World')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(content.writes, isEmpty);
    expect(find.text('World'), findsOneWidget);
  });

  testWidgets('adding a server sends name and address', (tester) async {
    await pump(tester, ContentKind.servers);
    expect(find.text('No servers yet.'), findsOneWidget);

    await tester.tap(find.byKey(const m3.ValueKey('content-add-server')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const m3.ValueKey('server-address')),
      'play.example.com',
    );
    await tester.tap(find.byKey(const m3.ValueKey('server-save')));
    await tester.pumpAndSettle();

    // An unnamed server takes its address as the name, which is what the game shows.
    expect(content.writes, ['server:play.example.com@play.example.com']);
    expect(find.text('play.example.com'), findsWidgets);
  });

  testWidgets('an empty folder explains itself and offers nothing to toggle', (
    tester,
  ) async {
    await pump(tester, ContentKind.shaderPacks);

    expect(find.text('No shader packs yet.'), findsOneWidget);
    expect(find.byType(m3.Switch), findsNothing);
  });
}
