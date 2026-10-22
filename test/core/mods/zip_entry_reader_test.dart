import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/mods/zip_entry_reader.dart';
import 'package:path/path.dart' as p;

/// Builds a real zip, since the point of the reader is the on-disk format.
File buildJar(
  Directory dir,
  String name,
  Map<String, String> files, {
  bool store = false,
}) {
  final archive = Archive();
  files.forEach((path, content) {
    final bytes = utf8.encode(content);
    archive.addFile(
      ArchiveFile(path, bytes.length, bytes)
        // The encoder honours this per entry; the default is deflate.
        ..compression = store ? CompressionType.none : CompressionType.deflate,
    );
  });
  final file = File(p.join(dir.path, name));
  file.writeAsBytesSync(ZipEncoder().encode(archive));
  return file;
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('zip-reader'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('reads a deflated entry without touching the rest', () async {
    // 2 MB of filler in front of a 40-byte descriptor: the old implementation
    // inflated all of it to read the 40 bytes.
    final filler = 'x' * (2 * 1024 * 1024);
    final file = buildJar(tmp, 'mod.jar', {
      'assets/huge.bin': filler,
      'fabric.mod.json': '{"id":"sodium","name":"Sodium","version":"0.5.11"}',
    });

    final reader = await ZipEntryReader.open(file);
    addTearDown(reader.close);

    final entry = await reader.read('fabric.mod.json');
    expect(entry, isNotNull);
    expect(utf8.decode(entry!), contains('"id":"sodium"'));

    // ...and the filler is still readable when asked for by name.
    final big = await reader.read('assets/huge.bin');
    expect(big!.length, filler.length);
  });

  test('reads a stored (uncompressed) entry', () async {
    // `store: true` writes the entry uncompressed (method 0).
    final file = buildJar(tmp, 'stored.jar', {
      'META-INF/mods.toml': '[[mods]]\nmodId="jei"\n',
    }, store: true);

    final reader = await ZipEntryReader.open(file);
    addTearDown(reader.close);

    expect(
      await reader.read('META-INF/mods.toml'),
      isNotNull,
      reason: 'method 0 must be handled, not only deflate',
    );
  });

  test('readFirst picks the first name that exists', () async {
    final file = buildJar(tmp, 'both.jar', {
      'quilt.mod.json': '{"quilt_loader":{"id":"q"}}',
      'fabric.mod.json': '{"id":"f"}',
    });

    final reader = await ZipEntryReader.open(file);
    addTearDown(reader.close);

    final text = await reader.readFirst(['quilt.mod.json', 'fabric.mod.json']);
    expect(text, contains('quilt_loader'));
  });

  test('a missing entry is null, not an error', () async {
    final file = buildJar(tmp, 'plain.jar', {'a.txt': 'hello'});

    final reader = await ZipEntryReader.open(file);
    addTearDown(reader.close);

    expect(await reader.read('fabric.mod.json'), isNull);
    expect(await reader.readFirst(['x.json', 'y.toml']), isNull);
  });

  test('a file that is not a zip has no entries', () async {
    final file = File(p.join(tmp.path, 'not-a-zip.jar'))
      ..writeAsStringSync('this is not a zip at all');

    final reader = await ZipEntryReader.open(file);
    addTearDown(reader.close);

    // The scanner checks the PK signature first; the reader stays quiet rather
    // than throwing out of a metadata read.
    expect(await reader.read('fabric.mod.json'), isNull);
  });

  test('an empty zip directory is an empty map', () async {
    final file = File(p.join(tmp.path, 'empty.jar'))
      ..writeAsBytesSync(ZipEncoder().encode(Archive()));

    final reader = await ZipEntryReader.open(file);
    addTearDown(reader.close);

    expect(await reader.read('anything'), isNull);
  });
}
