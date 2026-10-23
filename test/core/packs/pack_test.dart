import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/core/packs/mrpack.dart';
import 'package:oh_my_mc/core/packs/mrpack_importer.dart';
import 'package:oh_my_mc/core/packs/pack_exporter.dart';
import 'package:oh_my_mc/core/packs/pack_importer.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('packs'));
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  /// A `.mrpack` is a zip: manifest + overrides, no jars.
  File writeMrpack({
    String name = 'Fabulously Optimized',
    String minecraft = '1.20.1',
    Map<String, Object?> dependencies = const {'fabric-loader': '0.16.9'},
    List<Map<String, Object?>> files = const [],
    Map<String, String> overrides = const {},
  }) {
    final archive = Archive()
      ..addFile(
        ArchiveFile(
          'modrinth.index.json',
          utf8
              .encode(
                jsonEncode({
                  'formatVersion': 1,
                  'game': 'minecraft',
                  'name': name,
                  'versionId': '1.0',
                  'dependencies': {'minecraft': minecraft, ...dependencies},
                  'files': files,
                }),
              )
              .length,
          utf8.encode(
            jsonEncode({
              'formatVersion': 1,
              'game': 'minecraft',
              'name': name,
              'versionId': '1.0',
              'dependencies': {'minecraft': minecraft, ...dependencies},
              'files': files,
            }),
          ),
        ),
      );
    for (final entry in overrides.entries) {
      final bytes = utf8.encode(entry.value);
      archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
    }
    final file = File(p.join(tmp.path, 'pack.mrpack'))
      ..writeAsBytesSync(ZipEncoder().encode(archive));
    return file;
  }

  group('manifest', () {
    test('reads the loader and game version', () {
      final index = MrpackIndex.parse(
        jsonEncode({
          'formatVersion': 1,
          'name': 'Sodium Pack',
          'dependencies': {'minecraft': '1.20.1', 'fabric-loader': '0.16.9'},
          'files': [
            {
              'path': 'mods/sodium.jar',
              'downloads': ['https://cdn.modrinth.com/sodium.jar'],
              'fileSize': 10,
              'hashes': {'sha1': 'abc'},
              'env': {'client': 'required', 'server': 'unsupported'},
            },
          ],
        }),
      );

      expect(index.minecraft, '1.20.1');
      expect(index.loader, LoaderKind.fabric);
      expect(index.loaderVersion, '0.16.9');
      expect(index.clientFiles.single.path, 'mods/sodium.jar');
    });

    test('a server-only file is not installed on the client', () {
      final index = MrpackIndex.parse(
        jsonEncode({
          'formatVersion': 1,
          'dependencies': {'minecraft': '1.20.1'},
          'files': [
            {
              'path': 'mods/serveronly.jar',
              'downloads': ['https://example.invalid/a.jar'],
              'env': {'client': 'unsupported'},
            },
            {
              'path': 'mods/client.jar',
              'downloads': ['https://example.invalid/b.jar'],
            },
          ],
        }),
      );

      expect(index.clientFiles.map((f) => f.path), ['mods/client.jar']);
    });

    test('a future format is refused rather than misread', () {
      expect(
        () => MrpackIndex.parse(
          jsonEncode({
            'formatVersion': 9,
            'dependencies': {'minecraft': '1.20.1'},
          }),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('neoforge packs derive the loader and its version', () {
      final index = MrpackIndex.parse(
        jsonEncode({
          'formatVersion': 1,
          'dependencies': {'minecraft': '1.21.1', 'neoforge': '21.1.264'},
          'files': [],
        }),
      );

      expect(index.loader, LoaderKind.neoforge);
      expect(index.loaderVersion, '21.1.264');
    });
  });

  group('mrpack import', () {
    test('overrides are unpacked and win over the manifest', () async {
      final pack = writeMrpack(
        overrides: {
          'overrides/config/sodium-options.json': '{"quality":"high"}',
          // client-overrides is applied to a client too, after overrides.
          'client-overrides/config/sodium-options.json': '{"quality":"ultra"}',
        },
      );
      final game = Directory(p.join(tmp.path, 'game'));

      final result = await MrpackImporter().import(pack, gameDir: game);

      expect(result.overrideCount, 2);
      expect(
        File(p.join(game.path, 'config/sodium-options.json'))
            .readAsStringSync(),
        '{"quality":"ultra"}',
        reason: 'client-overrides must win for a client install',
      );
      expect(result.index.minecraft, '1.20.1');
    });

    test('a path that escapes the instance is refused', () async {
      final pack = writeMrpack(
        overrides: {'overrides/../../../escaped.txt': 'nope'},
      );

      final result = await MrpackImporter().import(
        pack,
        gameDir: Directory(p.join(tmp.path, 'game')),
      );

      expect(result.overrideCount, 0);
      expect(File(p.join(tmp.path, 'escaped.txt')).existsSync(), isFalse);
    });

    test('a zip without a manifest is not a pack', () async {
      final archive = Archive()
        ..addFile(ArchiveFile('hello.txt', 5, utf8.encode('hello')));
      final notAPack = File(p.join(tmp.path, 'random.zip'))
        ..writeAsBytesSync(ZipEncoder().encode(archive));

      await expectLater(
        PackImporter().import(
          notAPack,
          gameDir: Directory(p.join(tmp.path, 'game')),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('export and reimport', () {
    test('a launcher pack round-trips its files and metadata', () async {
      final game = Directory(p.join(tmp.path, 'source'))
        ..createSync(recursive: true);
      Directory(p.join(game.path, 'mods')).createSync();
      Directory(p.join(game.path, 'saves/world')).createSync(recursive: true);
      // Rebuildable and noisy folders must not be in the pack.
      Directory(p.join(game.path, 'libraries')).createSync();
      Directory(p.join(game.path, 'logs')).createSync();

      File(p.join(game.path, 'options.txt')).writeAsStringSync('fov:90');
      File(p.join(game.path, 'mods/sodium.jar')).writeAsStringSync('jar');
      File(p.join(game.path, 'saves/world/level.dat'))
          .writeAsStringSync('world');
      File(p.join(game.path, 'libraries/big.jar')).writeAsStringSync('big');
      File(p.join(game.path, 'logs/latest.log')).writeAsStringSync('log');

      final out = File(p.join(tmp.path, 'pack.zip'));
      final count = await PackExporter().export(
        instance: const Instance(
          id: 'demo',
          name: 'Demo Pack',
          versionId: '1.20.1',
          loader: LoaderKind.fabric,
          loaderVersion: '0.16.9',
        ),
        gameDir: game,
        out: out,
      );

      expect(count, 4, reason: 'manifest + options + mod + save');

      final target = Directory(p.join(tmp.path, 'restored'));
      final imported = await PackImporter().import(out, gameDir: target);

      expect(imported.kind, PackKind.launcher);
      expect(imported.name, 'Demo Pack');
      expect(imported.gameVersion, '1.20.1');
      expect(imported.loader, LoaderKind.fabric);
      expect(imported.loaderVersion, '0.16.9');
      expect(
        File(p.join(target.path, 'mods/sodium.jar')).readAsStringSync(),
        'jar',
      );
      expect(
        File(p.join(target.path, 'saves/world/level.dat')).readAsStringSync(),
        'world',
        reason: 'saves are part of the instance',
      );
      expect(
        File(p.join(target.path, 'libraries/big.jar')).existsSync(),
        isFalse,
      );
      expect(
        File(p.join(target.path, 'logs/latest.log')).existsSync(),
        isFalse,
      );
    });

    test('the manifest is not unpacked into the game directory', () async {
      final game = Directory(p.join(tmp.path, 'source'))..createSync();
      final out = File(p.join(tmp.path, 'p.zip'));
      await PackExporter().export(
        instance: const Instance(id: 'a', name: 'A', versionId: '1.20.1'),
        gameDir: game,
        out: out,
      );

      final target = Directory(p.join(tmp.path, 'restored'));
      await PackImporter().import(out, gameDir: target);

      expect(
        File(p.join(target.path, PackExporter.manifestName)).existsSync(),
        isFalse,
      );
    });
  });
}
