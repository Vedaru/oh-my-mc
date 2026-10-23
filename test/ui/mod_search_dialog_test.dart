import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/app/providers.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/core/mods/mod_installer.dart';
import 'package:oh_my_mc/core/mods/modrinth.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/data/modrinth_providers.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:oh_my_mc/ui/instances/content_search_dialog.dart';
import 'package:path/path.dart' as p;

import '../support/harness.dart';

/// What the dialog is responsible for: showing results that fit the instance,
/// and telling the user what happened to each install. The network and the disk
/// are replaced here - `test/core/mods/modrinth_test.dart` owns those.
void main() {
  late Directory tmp;
  late List<ContentInstallRequest> requests;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('mod-search');
    requests = [];
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<void> pump(
    WidgetTester tester, {
    required String versionId,
    List<ModrinthProject> results = const [],
    ModInstallOutcome? outcome,
    Object? installError,
    List<ContentSearchQuery>? queries,
  }) async {
    final container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWith(
          (ref) => MemorySettingsStore(AppSettings.defaults),
        ),
        launcherPathsProvider.overrideWithValue(
          LauncherPaths(data: tmp, game: Directory(p.join(tmp.path, 'game'))),
        ),
        contentSearchProvider.overrideWith((ref, query) async {
          queries?.add(query);
          return results;
        }),
        contentInstallActionProvider.overrideWith(
          (ref) => (request) async {
            requests.add(request);
            if (installError != null) throw installError;
            return outcome ??
                const ModInstallOutcome(
                  installed: ['sodium.jar'],
                  skipped: [],
                  failed: {},
                );
          },
        ),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpScreen(
      tester,
      container,
      ContentSearchDialog(
        instance: Instance(id: 'a', name: 'Demo', versionId: versionId),
        kind: CatalogKind.mod,
      ),
    );
  }

  testWidgets('a modded instance searches with its loader and game version', (
    tester,
  ) async {
    final queries = <ContentSearchQuery>[];
    await pump(
      tester,
      versionId: 'fabric-loader-0.16.9-1.20.1',
      results: const [
        ModrinthProject(
          id: 'sodium',
          slug: 'sodium',
          title: 'Sodium',
          description: 'Rendering engine',
          downloads: 100,
        ),
      ],
      queries: queries,
    );
    await tester.pumpAndSettle();

    // The filters come from the instance and are stated, not configured.
    expect(find.textContaining('fabric'), findsOneWidget);
    expect(find.textContaining('1.20.1'), findsOneWidget);
    expect(queries.single.gameVersion, '1.20.1');
    expect(queries.single.loader, 'fabric');
    expect(find.text('Sodium'), findsOneWidget);
  });

  testWidgets('installing marks the row and refreshes the mod list', (
    tester,
  ) async {
    await pump(
      tester,
      versionId: '1.20.1-forge-47.4.28',
      results: const [
        ModrinthProject(
          id: 'jei',
          slug: 'jei',
          title: 'JEI',
          description: 'Item recipes',
          downloads: 5,
        ),
      ],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Install'));
    await tester.pumpAndSettle();

    expect(requests, hasLength(1));
    expect(requests.single.project.id, 'jei');
    expect(requests.single.gameVersion, '1.20.1');
    expect(requests.single.loader, 'forge');
    // The button is replaced by a check: the same row cannot be installed twice,
    // and the dialog stays open so the user can add another.
    expect(find.text('Install'), findsNothing);
    expect(find.byIcon(m3.Icons.check), findsOneWidget);
  });

  testWidgets('a failed install keeps its reason on the row', (tester) async {
    await pump(
      tester,
      versionId: 'fabric-loader-0.16.9-1.20.1',
      results: const [
        ModrinthProject(
          id: 'broken',
          slug: 'broken',
          title: 'Broken',
          description: '',
          downloads: 1,
        ),
      ],
      outcome: const ModInstallOutcome(
        installed: [],
        skipped: [],
        failed: {'broken.jar': 'HTTP 404 from cdn.modrinth.com'},
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Install'));
    await tester.pumpAndSettle();

    expect(find.textContaining('HTTP 404'), findsOneWidget);
    // Not marked done: the row has to stay installable.
    expect(find.text('Install'), findsOneWidget);
  });

  testWidgets('a vanilla instance is told why there is nothing to search', (
    tester,
  ) async {
    await pump(tester, versionId: '1.20.1');
    await tester.pumpAndSettle();

    expect(find.text('This version cannot take mods'), findsWidgets);
    // No search field that would only ever return unusable results.
    expect(find.byKey(const m3.ValueKey('content-search')), findsNothing);
  });
}
