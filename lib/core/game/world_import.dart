import 'dart:io';

import 'package:path/path.dart' as p;

import '../mods/zip_entry_reader.dart';

/// Imports a world from a `.zip` into `saves/`.
///
/// A world zip in the wild has two shapes: the archive *is* the world (`level.dat`
/// at the top) or it wraps one folder (`My World/level.dat`). Both are accepted, and
/// the world name comes from that folder - or from the file name when there is no
/// wrapper. Anything else is refused with the reason, because a half-unpacked save
/// makes the game list a world that crashes on load.
class WorldImporter {
  const WorldImporter();

  /// Marker that makes a directory a world.
  static const levelDat = 'level.dat';

  Future<WorldImportResult> importZip(
    File zip, {
    required Directory savesDir,
    String? name,
  }) async {
    final reader = await ZipEntryReader.open(zip);
    try {
      final entries = [
        for (final entry in reader.names)
          if (!entry.endsWith('/')) entry,
      ];

      final layout = _layoutOf(entries, zip);
      if (layout == null) {
        throw const FormatException(
          'not a world: no level.dat inside the archive',
        );
      }

      final target = Directory(p.join(savesDir.path, name ?? layout.worldName));
      if (await target.exists()) {
        throw StateError(
          'a world called "${p.basename(target.path)}" already exists',
        );
      }

      var written = 0;
      for (final entry in entries) {
        final relative = entry.substring(layout.prefix.length);
        if (relative.isEmpty) continue;
        final destination = _safeJoin(target, relative);
        if (destination == null) continue;
        final bytes = await reader.read(entry);
        if (bytes == null) continue;
        await Directory(p.dirname(destination)).create(recursive: true);
        await File(destination).writeAsBytes(bytes, flush: true);
        written++;
      }

      return WorldImportResult(path: target.path, files: written);
    } finally {
      await reader.close();
    }
  }

  /// Which directory inside the archive is the world, and what it is called.
  static ({String prefix, String worldName})? _layoutOf(
    List<String> entries,
    File zip,
  ) {
    // `level.dat` at the root: the archive is the world.
    if (entries.contains(levelDat)) {
      return (prefix: '', worldName: p.basenameWithoutExtension(zip.path));
    }
    // Exactly one nested `level.dat`, one directory deep.
    for (final entry in entries) {
      if (p.basename(entry) != levelDat) continue;
      final prefix = entry.substring(0, entry.length - levelDat.length);
      if (p.split(prefix).where((s) => s.isNotEmpty).length != 1) continue;
      return (
        prefix: prefix,
        worldName: p.split(prefix).firstWhere((s) => s.isNotEmpty),
      );
    }
    return null;
  }

  static String? _safeJoin(Directory root, String relative) {
    final normalised = p.normalize(relative);
    if (p.isAbsolute(normalised) || normalised.startsWith('..')) return null;
    final target = p.normalize(p.join(root.path, normalised));
    return p.isWithin(root.path, target) ? target : null;
  }
}

class WorldImportResult {
  const WorldImportResult({required this.path, required this.files});

  final String path;
  final int files;
}
