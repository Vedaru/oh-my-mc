import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/game/content.dart';
import 'package:oh_my_mc/core/game/world_import.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late Directory saves;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('world-import');
    saves = Directory(p.join(tmp.path, 'saves'))..createSync(recursive: true);
  });
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  File zipOf(String name, Map<String, String> entries) {
    final archive = Archive();
    for (final entry in entries.entries) {
      final bytes = utf8.encode(entry.value);
      archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
    }
    return File(p.join(tmp.path, name))
      ..writeAsBytesSync(ZipEncoder().encode(archive));
  }

  test('a wrapped world takes the folder name and lands in saves/', () async {
    final zip = zipOf('download.zip', {
      'Skyblock/level.dat': 'level',
      'Skyblock/region/r.0.0.mca': 'region',
      'Skyblock/icon.png': 'png',
    });

    final result = await const WorldImporter().importZip(zip, savesDir: saves);

    expect(p.basename(result.path), 'Skyblock');
    expect(result.files, 3);
    expect(File(p.join(result.path, 'level.dat')).readAsStringSync(), 'level');
    expect(
      File(p.join(result.path, 'region/r.0.0.mca')).readAsStringSync(),
      'region',
    );
  });

  test('a bare world takes the zip name', () async {
    final zip = zipOf('My World.zip', {
      'level.dat': 'level',
      'region/x.mca': 'region',
    });

    final result = await const WorldImporter().importZip(zip, savesDir: saves);

    expect(p.basename(result.path), 'My World');
    expect(File(p.join(result.path, 'level.dat')).existsSync(), isTrue);
  });

  test('an explicit name wins', () async {
    final zip = zipOf('x.zip', {'level.dat': 'l'});

    final result = await const WorldImporter().importZip(
      zip,
      savesDir: saves,
      name: 'Renamed',
    );

    expect(p.basename(result.path), 'Renamed');
  });

  test('a zip without level.dat is refused, not half-unpacked', () async {
    final zip = zipOf('not-a-world.zip', {'readme.txt': 'hi'});

    await expectLater(
      const WorldImporter().importZip(zip, savesDir: saves),
      throwsA(isA<FormatException>()),
    );
    expect(saves.listSync(), isEmpty);
  });

  test('an existing world is not overwritten', () async {
    Directory(p.join(saves.path, 'Skyblock')).createSync();
    final zip = zipOf('download.zip', {'Skyblock/level.dat': 'level'});

    await expectLater(
      const WorldImporter().importZip(zip, savesDir: saves),
      throwsA(isA<StateError>()),
    );
  });

  test('an imported world shows up in the content list', () async {
    final zip = zipOf('pack.zip', {'level.dat': 'level'});
    final result = await const WorldImporter().importZip(zip, savesDir: saves);

    final worlds = await GameContent(tmp.path).list(ContentKind.saves);

    expect(worlds.map((w) => w.name), [p.basename(result.path)]);
  });

  test('a path that escapes the world directory is dropped', () async {
    final zip = zipOf('evil.zip', {
      'level.dat': 'level',
      '../../escaped.txt': 'nope',
    });

    final result = await const WorldImporter().importZip(zip, savesDir: saves);

    expect(File(p.join(tmp.path, 'escaped.txt')).existsSync(), isFalse);
    expect(result.files, 1);
  });
}
