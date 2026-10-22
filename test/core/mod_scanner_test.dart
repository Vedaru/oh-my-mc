import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/mods/mod_scanner.dart';
import 'package:path/path.dart' as p;

/// Builds a real zip, because the scanner's whole job is reading one: fabricating
/// an `Archive` object would test the parser against itself.
String writeJar(Directory dir, String name, Map<String, Object> files) {
  final archive = Archive();
  files.forEach((path, content) {
    final bytes = utf8.encode(
      content is String ? content : jsonEncode(content),
    );
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  });
  final file = File(p.join(dir.path, name));
  file.writeAsBytesSync(ZipEncoder().encode(archive));
  return file.path;
}

void main() {
  late Directory mods;

  setUp(() {
    mods = Directory.systemTemp.createTempSync('omc-mods');
  });

  tearDown(() {
    if (mods.existsSync()) mods.deleteSync(recursive: true);
  });

  group('metadata', () {
    test('fabric.mod.json', () async {
      writeJar(mods, 'sodium.jar', {
        'fabric.mod.json': {
          'id': 'sodium',
          'name': 'Sodium',
          'version': '0.5.11',
          'authors': ['jellysquid3', 'IMS'],
        },
        'sodium.class': 'x',
      });

      final mod = await readMod(p.join(mods.path, 'sodium.jar'));

      expect(mod.loader, ModLoaderKind.fabric);
      expect(mod.id, 'sodium');
      expect(mod.displayName, 'Sodium');
      expect(mod.version, '0.5.11');
      expect(mod.authors, 'jellysquid3, IMS');
      expect(mod.enabled, isTrue);
      expect(mod.problem, isNull);
    });

    test('quilt.mod.json, including contributor objects', () async {
      writeJar(mods, 'qsl.jar', {
        'quilt.mod.json': {
          'quilt_loader': {
            'id': 'qsl',
            'version': '5.0.0',
            'metadata': {
              'name': 'Quilt Standard Libraries',
              'contributors': [
                {'name': 'QuiltMC'},
              ],
            },
          },
        },
      });

      final mod = await readMod(p.join(mods.path, 'qsl.jar'));

      expect(mod.loader, ModLoaderKind.quilt);
      expect(mod.displayName, 'Quilt Standard Libraries');
      expect(mod.authors, 'QuiltMC');
    });

    test('mods.toml reads the first [[mods]] table only', () async {
      writeJar(mods, 'jei.jar', {
        'META-INF/mods.toml': '''
modLoader="javafml"
loaderVersion="[47,)"

[[mods]]
modId="jei"
version="15.2.0.27"
displayName="Just Enough Items"
authors="mezz"

[[dependencies.jei]]
    modId="minecraft"
''',
      });

      final mod = await readMod(p.join(mods.path, 'jei.jar'));

      expect(mod.loader, ModLoaderKind.forge);
      expect(mod.id, 'jei');
      expect(mod.displayName, 'Just Enough Items');
      expect(mod.version, '15.2.0.27');
      expect(mod.authors, 'mezz');
    });

    test('neoforge.mods.toml wins over a stale mods.toml', () async {
      writeJar(mods, 'neo.jar', {
        'META-INF/neoforge.mods.toml': '''
[[mods]]
modId="neothing"
version="1.0.0"
displayName="Neo Thing"
''',
      });

      final mod = await readMod(p.join(mods.path, 'neo.jar'));

      expect(mod.loader, ModLoaderKind.neoforge);
      expect(mod.displayName, 'Neo Thing');
    });

    test(
      r'a ${file.jarVersion} placeholder is not shown as a version',
      () async {
        writeJar(mods, 'placeholder.jar', {
          'META-INF/mods.toml': '''
[[mods]]
modId="ph"
version="\${file.jarVersion}"
displayName="Placeholder"
''',
        });

        final mod = await readMod(p.join(mods.path, 'placeholder.jar'));

        expect(mod.version, isNull);
        expect(mod.displayName, 'Placeholder');
      },
    );

    test('mcmod.info (1.12 and older)', () async {
      writeJar(mods, 'legacy.jar', {
        'mcmod.info': [
          {
            'modid': 'oldmod',
            'name': 'Old Mod',
            'version': '1.2.3',
            'authorList': ['someone'],
          },
        ],
      });

      final mod = await readMod(p.join(mods.path, 'legacy.jar'));

      expect(mod.loader, ModLoaderKind.legacyForge);
      expect(mod.displayName, 'Old Mod');
      expect(mod.version, '1.2.3');
    });

    test('a jar with no descriptor is kept and named, not hidden', () async {
      writeJar(mods, 'library.jar', {'com/example/Lib.class': 'x'});

      final mod = await readMod(p.join(mods.path, 'library.jar'));

      expect(mod.loader, ModLoaderKind.unknown);
      expect(mod.problem, 'no mod metadata in the jar');
      expect(mod.displayName, 'library.jar');
    });

    test('a corrupt jar reports why instead of blanking the list', () async {
      File(p.join(mods.path, 'broken.jar')).writeAsStringSync('not a zip');

      final modsList = await scanMods(mods.path);

      expect(modsList, hasLength(1));
      // Not "no metadata": a renamed text file is not a jar at all, and the row
      // has to say so or the user keeps wondering what they dropped in.
      expect(modsList.single.problem, contains('no zip signature'));
    });
  });

  group('scan', () {
    test('lists enabled and disabled jars, sorted by name', () async {
      writeJar(mods, 'zeta.jar', {
        'fabric.mod.json': {'id': 'zeta', 'name': 'Zeta', 'version': '1'},
      });
      writeJar(mods, 'alpha.jar.disabled', {
        'fabric.mod.json': {'id': 'alpha', 'name': 'Alpha', 'version': '1'},
      });
      // Not a mod: ignored, because the loader ignores it too.
      File(p.join(mods.path, 'notes.txt')).writeAsStringSync('hello');

      final list = await scanMods(mods.path);

      expect(list.map((m) => m.displayName), ['Alpha', 'Zeta']);
      expect(list.first.enabled, isFalse);
      expect(list.last.enabled, isTrue);
    });

    test('a missing folder is an empty list, not an error', () async {
      expect(await scanMods(p.join(mods.path, 'nope')), isEmpty);
    });
  });

  group('enable and disable', () {
    test('a rename is the whole mechanism', () async {
      final path = writeJar(mods, 'sodium.jar', {
        'fabric.mod.json': {'id': 'sodium', 'name': 'Sodium', 'version': '1'},
      });
      final mod = await readMod(path);

      final disabled = await setModEnabled(mod, false);
      expect(disabled, '$path.disabled');
      expect(File(disabled).existsSync(), isTrue);
      expect(File(path).existsSync(), isFalse);
      // Nobody remembers the enabled set: the next scan sees the suffix.
      final rescanned = await scanMods(mods.path);
      expect(rescanned.single.enabled, isFalse);

      final enabled = await setModEnabled(rescanned.single, true);
      expect(enabled, path);
      expect(File(path).existsSync(), isTrue);
    });

    test(
      'both files existing is refused rather than overwriting one',
      () async {
        final path = writeJar(mods, 'dup.jar', {
          'fabric.mod.json': {'id': 'dup', 'name': 'Dup', 'version': '1'},
        });
        writeJar(mods, 'dup.jar.disabled', {
          'fabric.mod.json': {'id': 'dup', 'name': 'Dup', 'version': '1'},
        });
        final mod = await readMod(path);

        await expectLater(
          setModEnabled(mod, false),
          throwsA(isA<FileSystemException>()),
        );
        // Neither file was touched.
        expect(File(path).existsSync(), isTrue);
        expect(File('$path.disabled').existsSync(), isTrue);
      },
    );

    test('asking for the state it is already in does nothing', () async {
      final path = writeJar(mods, 'same.jar', {
        'fabric.mod.json': {'id': 'same', 'name': 'Same', 'version': '1'},
      });
      final mod = await readMod(path);

      expect(await setModEnabled(mod, true), path);
      expect(File(path).existsSync(), isTrue);
    });
  });

  test('delete removes the jar and leaves the others alone', () async {
    final a = writeJar(mods, 'a.jar', {
      'fabric.mod.json': {'id': 'a', 'name': 'A', 'version': '1'},
    });
    writeJar(mods, 'b.jar', {
      'fabric.mod.json': {'id': 'b', 'name': 'B', 'version': '1'},
    });

    await deleteMod(await readMod(a));

    expect(File(a).existsSync(), isFalse);
    expect((await scanMods(mods.path)).map((m) => m.displayName), ['B']);
  });
}
