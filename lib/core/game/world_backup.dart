import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// A world backup: one zip next to the saves, plus what it contains.
class WorldBackup {
  const WorldBackup({
    required this.file,
    required this.worldName,
    required this.entries,
    required this.sizeBytes,
  });

  final File file;
  final String worldName;
  final int entries;
  final int sizeBytes;

  String get fileName => p.basename(file.path);
}

/// Copies a save folder into a zip the launcher can put back.
///
/// A world is the one thing in an instance that cannot be reinstalled: mods and packs
/// are downloads, a world is hours. This is the launcher's side of "I am about to
/// change the mods, take a copy first".
///
/// The zip is named `<world>-<timestamp>.zip` and lands in the instance's `backups/`
/// (next to `saves/`, not inside it) so the game never sees a stray archive where it
/// expects a world folder.
class WorldBackupService {
  const WorldBackupService();

  /// Zip [world] into [backupsDir]. Throws if the world is not a directory: an empty
  /// backup of a missing world is worse than a failure, because it looks like one.
  Future<WorldBackup> backUp(
    Directory world, {
    required Directory backupsDir,
  }) async {
    if (!await world.exists()) {
      throw ArgumentError('no such world: ${world.path}');
    }
    await backupsDir.create(recursive: true);

    final worldName = p.basename(world.path);
    final stamp = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final name =
        '$worldName-${stamp.year}${two(stamp.month)}${two(stamp.day)}'
        '-${two(stamp.hour)}${two(stamp.minute)}${two(stamp.second)}.zip';
    final file = File(p.join(backupsDir.path, name));

    final encoder = ZipFileEncoder();
    encoder.create(file.path);
    var entries = 0;
    try {
      await for (final entity in world.list(recursive: true)) {
        if (entity is! File) continue;
        final relative = p.relative(entity.path, from: world.path);
        await encoder.addFile(entity, relative);
        entries++;
      }
    } finally {
      await encoder.close();
    }
    return WorldBackup(
      file: file,
      worldName: worldName,
      entries: entries,
      sizeBytes: await file.length(),
    );
  }

  /// The backups already on disk, newest first.
  Future<List<File>> listBackups(Directory backupsDir) async {
    if (!await backupsDir.exists()) return const [];
    final files = <File>[];
    await for (final entity in backupsDir.list()) {
      if (entity is File && entity.path.endsWith('.zip')) files.add(entity);
    }
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  /// Puts a backup back as a save folder. Refuses to overwrite an existing world: a
  /// restore that silently replaces hours of play is a data loss feature.
  Future<Directory> restore(File archive, {required Directory savesDir}) async {
    final name = p.basenameWithoutExtension(archive.path);
    // `world-20261023-140501` → `world (restored 20261023-140501)`: the restored copy
    // sits beside the original rather than on top of it. The stamp is a fixed 15
    // characters, so a world name with dashes in it splits correctly; splitting on the
    // last dash does not, because the stamp contains one.
    const stampLength = 15; // YYYYMMDD-HHMMSS
    final hasStamp = name.length > stampLength + 1;
    final worldName = hasStamp
        ? name.substring(0, name.length - stampLength - 1)
        : name;
    final suffix = hasStamp
        ? name.substring(name.length - stampLength)
        : 'copy';
    final target = Directory(
      p.join(savesDir.path, '$worldName (restored $suffix)'),
    );
    if (await target.exists()) {
      throw ArgumentError('already restored: ${target.path}');
    }
    await target.create(recursive: true);
    await extractFileToDisk(archive.path, target.path);
    return target;
  }
}
