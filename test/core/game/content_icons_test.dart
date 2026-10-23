import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/game/content_icons.dart';
import 'package:path/path.dart' as p;

/// A pack's icon comes out of its zip, a world's out of its folder, and anything odd
/// falls back to "no icon" rather than to an error.
void main() {
  late Directory tmp;

  setUp(
    () async => tmp = await Directory.systemTemp.createTemp('content-icons'),
  );
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<File> packWith({required Map<String, List<int>> entries}) async {
    final file = File(p.join(tmp.path, 'Pack.zip'));
    final encoder = ZipFileEncoder()..create(file.path);
    for (final entry in entries.entries) {
      encoder.addArchiveFile(
        ArchiveFile(entry.key, entry.value.length, entry.value),
      );
    }
    await encoder.close();
    return file;
  }

  final png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3];

  test('a pack icon is read from pack.png inside the zip', () async {
    final file = await packWith(
      entries: {'pack.mcmeta': '{}'.codeUnits, 'pack.png': png},
    );

    final icon = await const ContentIcons().forEntry(
      file.path,
      isDirectory: false,
    );

    expect(icon, png);
  });

  test('a pack without an icon is simply no icon', () async {
    final file = await packWith(entries: {'pack.mcmeta': '{}'.codeUnits});

    expect(
      await const ContentIcons().forEntry(file.path, isDirectory: false),
      isNull,
    );
  });

  test('a world icon is read from icon.png in its folder', () async {
    final world = Directory(p.join(tmp.path, 'World'));
    await world.create();
    await File(p.join(world.path, 'icon.png')).writeAsBytes(png);

    final icon = await const ContentIcons().forEntry(
      world.path,
      isDirectory: true,
    );

    expect(icon, png);
  });

  test('a missing file is not an exception', () async {
    expect(
      await const ContentIcons().forEntry(
        p.join(tmp.path, 'nope.zip'),
        isDirectory: false,
      ),
      isNull,
    );
    expect(
      await const ContentIcons().forEntry(
        p.join(tmp.path, 'no-world'),
        isDirectory: true,
      ),
      isNull,
    );
  });

  test('an oversized icon is refused instead of decoded', () async {
    final file = await packWith(
      entries: {'pack.png': List<int>.filled(64 * 1024, 0)},
    );

    expect(
      await const ContentIcons(maxBytes: 1024)
          .forEntry(file.path, isDirectory: false),
      isNull,
    );
  });
}
