import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/core/mods/modrinth.dart';
import 'package:oh_my_mc/core/packs/mrpack.dart';
import 'package:oh_my_mc/core/packs/mrpack_importer.dart';
import 'package:oh_my_mc/core/packs/modpack_install.dart';
import 'package:path/path.dart' as p;

/// The orchestration, end to end, against a real `.mrpack` on disk.
///
/// The order is the feature: read the manifest, install *its* Minecraft version and
/// loader, create the instance, then apply the files. A test that faked the manifest
/// could not catch the real bug this guards - installing a pack into the version the user
/// happened to have selected.
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('modpack');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  /// A minimal but valid pack: an index with a name, a version and dependencies.
  List<int> packBytes({
    String name = 'Fabulously Optimized',
    String minecraft = '1.20.1',
    String loaderKey = 'fabric-loader',
    String loaderVersion = '0.15.11',
    List<Map<String, Object?>> files = const [],
  }) {
    final index = {
      'formatVersion': 1,
      'game': 'minecraft',
      'versionId': '3.0.0',
      'name': name,
      'summary': 'a pack',
      'files': files,
      'dependencies': {'minecraft': minecraft, loaderKey: loaderVersion},
    };
    final archive = Archive()
      ..addFile(
        ArchiveFile(
          'modrinth.index.json',
          utf8.encode(jsonEncode(index)).length,
          utf8.encode(jsonEncode(index)),
        ),
      );
    return ZipEncoder().encode(archive)!;
  }

  ModrinthVersion versionOf(String fileName) => ModrinthVersion(
    id: 'v1',
    projectId: 'proj',
    name: '3.0.0',
    versionNumber: '3.0.0',
    files: [
      ModrinthFile(
        url: 'https://cdn.example/$fileName',
        filename: fileName,
        sizeBytes: 1024,
        primary: true,
      ),
    ],
    dependencies: const [],
  );

  ModrinthProject project() => const ModrinthProject(
    id: 'proj',
    slug: 'fabulously-optimized',
    title: 'Fabulously Optimized',
    description: 'a pack',
    downloads: 10,
  );

  test('reads the manifest first, then installs what it names', () async {
    final cache = Directory(p.join(root.path, 'cache'));
    final installedVersion = <String, Object?>{};
    Instance? created;
    final log = <ModpackStep>[];

    final installer = ModpackInstaller(
      installVersion:
          ({
            required String minecraftVersion,
            required LoaderKind loader,
            String? loaderVersion,
          }) async {
            installedVersion['minecraft'] = minecraftVersion;
            installedVersion['loader'] = loader;
            installedVersion['loaderVersion'] = loaderVersion;
          },
      createInstance:
          ({
            required String name,
            required String versionId,
            LoaderKind loader = LoaderKind.vanilla,
            String? loaderVersion,
          }) async {
            created = Instance(
              id: 'fabulously-optimized',
              name: name,
              versionId: versionId,
              loader: loader,
              loaderVersion: loaderVersion,
            );
            return created!;
          },
      download: (url, target, {String sha1 = '', int size = 0, cancel}) async {
        await target.parent.create(recursive: true);
        await target.writeAsBytes(packBytes());
      },
      import: (pack, {required gameDir, onProgress}) async {
        // The real importer would fetch the manifest's files; this test's pack has
        // none, so what is asserted is the directory it was handed.
        await gameDir.create(recursive: true);
        File(p.join(gameDir.path, 'applied.txt')).writeAsStringSync('yes');
        return const MrpackImportResult(
          index: MrpackIndex(
            name: 'Fabulously Optimized',
            minecraft: '1.20.1',
            files: [],
          ),
          installed: [],
          skipped: [],
          failed: {},
          overrideCount: 0,
        );
      },
      cacheDir: cache,
      gameDir: (instance) =>
          Directory(p.join(root.path, 'instances', instance.id)),
    );

    final result = await installer.install(
      project: project(),
      version: versionOf('pack.mrpack'),
      name: 'Fabulously Optimized',
      onProgress: (step, detail) => log.add(step),
    );

    // The pack's own version and loader, not anything the caller passed.
    expect(installedVersion['minecraft'], '1.20.1');
    expect(installedVersion['loader'], LoaderKind.fabric);
    expect(installedVersion['loaderVersion'], '0.15.11');
    expect(created!.versionId, '1.20.1');
    expect(created!.loader, LoaderKind.fabric);
    // The steps happen in the order the dialog shows them.
    expect(log, [
      ModpackStep.download,
      ModpackStep.install,
      ModpackStep.create,
      ModpackStep.import,
    ]);
    expect(result.instance.name, 'Fabulously Optimized');
    // The downloaded pack is cleaned up: a second copy of something re-downloadable.
    expect(File(p.join(cache.path, 'pack.mrpack')).existsSync(), isFalse);
  });

  test('a forge pack installs forge, from the same manifest key', () async {
    var calledMc = '';
    LoaderKind? calledLoader;
    String? calledLoaderVersion;

    final installer = ModpackInstaller(
      installVersion:
          ({
            required String minecraftVersion,
            required LoaderKind loader,
            String? loaderVersion,
          }) async {
            calledMc = minecraftVersion;
            calledLoader = loader;
            calledLoaderVersion = loaderVersion;
          },
      createInstance: ({
        required String name,
        required String versionId,
        LoaderKind loader = LoaderKind.vanilla,
        String? loaderVersion,
      }) async => Instance(id: 'x', name: name, versionId: versionId),
      download: (url, target, {String sha1 = '', int size = 0, cancel}) async {
        await target.parent.create(recursive: true);
        await target.writeAsBytes(
          packBytes(
            minecraft: '1.19.2',
            loaderKey: 'forge',
            loaderVersion: '43.2.0',
          ),
        );
      },
      import: (pack, {required gameDir, onProgress}) async {
        await gameDir.create(recursive: true);
        return const MrpackImportResult(
          index: MrpackIndex(name: 'x', minecraft: '1.19.2', files: []),
          installed: [],
          skipped: [],
          failed: {},
          overrideCount: 0,
        );
      },
      cacheDir: Directory(p.join(root.path, 'cache')),
      gameDir: (instance) =>
          Directory(p.join(root.path, 'instances', instance.id)),
    );

    await installer.install(
      project: project(),
      version: versionOf('forge.mrpack'),
      name: 'Forge Pack',
    );

    expect(calledMc, '1.19.2');
    expect(calledLoader, LoaderKind.forge);
    expect(calledLoaderVersion, '43.2.0');
  });

  test('the loader names Modrinth writes map onto the installer kinds', () {
    expect(loaderKindOf('fabric-loader'), LoaderKind.fabric);
    expect(loaderKindOf('quilt-loader'), LoaderKind.quilt);
    expect(loaderKindOf('forge'), LoaderKind.forge);
    expect(loaderKindOf('neoforge'), LoaderKind.neoforge);
    expect(loaderKindOf(null), LoaderKind.vanilla);
    // Unknown is vanilla, not a crash: the pack still installs.
    expect(loaderKindOf('weird-loader'), LoaderKind.vanilla);
  });

  test('a pack without a file is refused, not installed half way', () async {
    final installer = ModpackInstaller(
      installVersion: ({
        required String minecraftVersion,
        required LoaderKind loader,
        String? loaderVersion,
      }) async => fail('must not install a version'),
      createInstance: ({
        required String name,
        required String versionId,
        LoaderKind loader = LoaderKind.vanilla,
        String? loaderVersion,
      }) async => fail('must not create an instance'),
      download: (url, target, {String sha1 = '', int size = 0, cancel}) async =>
          fail('must not download'),
      import: (pack, {required gameDir, onProgress}) async =>
          fail('must not import'),
      cacheDir: Directory(p.join(root.path, 'cache')),
      gameDir: (instance) => Directory(root.path),
    );

    await expectLater(
      installer.install(
        project: project(),
        version: const ModrinthVersion(
          id: 'v',
          projectId: 'proj',
          name: 'x',
          versionNumber: '1',
          files: [],
          dependencies: [],
        ),
        name: 'x',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
