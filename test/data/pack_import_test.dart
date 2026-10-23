import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/core/packs/pack_exporter.dart';
import 'package:oh_my_mc/core/packs/pack_importer.dart';
import 'package:oh_my_mc/data/instance_providers.dart';
import 'package:oh_my_mc/data/instance_store.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/data/pack_providers.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late PackImporter importer;
  late ProviderContainer container;
  late InstanceListNotifier controller;
  late LauncherPaths paths;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pack-import');
    importer = PackImporter();
    paths = LauncherPaths(data: tmp, game: Directory(p.join(tmp.path, 'game')));
    container = ProviderContainer(
      overrides: [
        instanceStoreProvider.overrideWith((ref) => MemoryInstanceStore()),
        launcherPathsProvider.overrideWithValue(paths),
      ],
    );
    controller = container.read(instanceListProvider.notifier);
    // `build` schedules the read; a turn of the event loop makes the list ready.
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() async {
    importer.close();
    container.dispose();
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('an mrpack becomes an instance named after the pack', () async {
    // Written by hand rather than through the exporter: this is the format a user
    // downloads from Modrinth, and it must be readable as-is.
    final file = File(p.join(tmp.path, 'pack.mrpack'));
    await file.writeAsBytes(
      _mrpack(
        name: 'Fabulously Optimized',
        minecraft: '1.20.1',
        loader: 'fabric-loader',
        loaderVersion: '0.16.9',
        files: const {},
      ),
    );

    final result = await importPackAsInstance(
      importer: importer,
      instances: controller,
      paths: paths,
      file: file,
    );

    expect(result.instance.name, 'Fabulously Optimized');
    expect(result.instance.versionId, '1.20.1');
    expect(result.instance.loader, LoaderKind.fabric);
    expect(result.instance.loaderVersion, '0.16.9');
    expect(controller.ready?.instances, hasLength(1));
    // The instance is selected: importing a pack and leaving the user on a list
    // they did not ask for would be a dead end.
    expect(controller.ready?.selectedId, result.instance.id);
  });

  test('export then import gives the same files', () async {
    final source = await controller.create(
      name: 'Survival',
      versionId: '1.20.1',
      loader: LoaderKind.fabric,
      loaderVersion: '0.16.9',
    );
    final gameDir = Directory(paths.gamePathsFor(source).root);
    Directory(p.join(gameDir.path, 'mods')).createSync(recursive: true);
    File(p.join(gameDir.path, 'mods/sodium.jar')).writeAsStringSync('jar');

    final out = File(p.join(tmp.path, 'survival.zip'));
    await exportInstancePack(
      exporter: PackExporter(),
      instance: source,
      paths: paths,
      out: out,
    );
    expect(out.existsSync(), isTrue);

    final restored = await importPackAsInstance(
      importer: importer,
      instances: controller,
      paths: paths,
      file: out,
    );

    expect(restored.instance.name, 'Survival');
    expect(restored.instance.loader, LoaderKind.fabric);
    final target = paths.gamePathsFor(restored.instance).root;
    expect(File(p.join(target, 'mods/sodium.jar')).readAsStringSync(), 'jar');
  });

  test(
    'a file that is not a pack is refused before an instance exists',
    () async {
      final file = File(p.join(tmp.path, 'notes.zip'))
        ..writeAsStringSync('not a zip');

      await expectLater(
        importPackAsInstance(
          importer: importer,
          instances: controller,
          paths: paths,
          file: file,
        ),
        throwsA(isA<Object>()),
      );
      // Nothing half-created: a failed import must not leave an empty instance.
      expect(controller.ready?.instances ?? const [], isEmpty);
    },
  );
}

/// A minimal mrpack, written with the archive package's encoder.
List<int> _mrpack({
  required String name,
  required String minecraft,
  required String loader,
  required String loaderVersion,
  required Map<String, String> files,
}) {
  final manifest = utf8.encode(
    jsonEncode({
      'formatVersion': 1,
      'game': 'minecraft',
      'name': name,
      'versionId': '1.0.0',
      'dependencies': {'minecraft': minecraft, loader: loaderVersion},
      'files': const [],
    }),
  );
  final archive = Archive()
    ..addFile(ArchiveFile('modrinth.index.json', manifest.length, manifest));
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return ZipEncoder().encode(archive);
}
