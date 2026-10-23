import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/game/world_backup.dart';
import 'package:path/path.dart' as p;

/// A world backup is judged by one thing: can the launcher put the world back. These
/// tests write a world, back it up, restore it into an empty saves folder and compare
/// the contents - the whole round trip, not just "a zip was created".
void main() {
  late Directory tmp;

  setUp(
    () async => tmp = await Directory.systemTemp.createTemp('world-backup'),
  );
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<Directory> makeWorld(String name) async {
    final world = Directory(p.join(tmp.path, 'saves', name));
    await Directory(p.join(world.path, 'region')).create(recursive: true);
    await File(p.join(world.path, 'level.dat')).writeAsBytes([1, 2, 3, 4]);
    await File(p.join(world.path, 'region', 'r.0.0.mca'))
        .writeAsString('chunks');
    return world;
  }

  test(
    'a backup holds every file, and restoring brings the world back',
    () async {
      final world = await makeWorld('Survival');
      final backups = Directory(p.join(tmp.path, 'backups'));
      const service = WorldBackupService();

      final backup = await service.backUp(world, backupsDir: backups);

      expect(backup.entries, 2, reason: 'level.dat and one region file');
      expect(backup.sizeBytes, greaterThan(0));
      expect(backup.fileName, startsWith('Survival-'));
      expect(backup.fileName, endsWith('.zip'));
      expect(await backups.list().length, 1);

      // Restore into a fresh saves folder: the copy must not land on the original.
      final fresh = Directory(p.join(tmp.path, 'restored-saves'));
      await fresh.create();
      final restored = await service.restore(backup.file, savesDir: fresh);

      expect(p.basename(restored.path), startsWith('Survival (restored '));
      expect(await File(p.join(restored.path, 'level.dat')).readAsBytes(), [
        1,
        2,
        3,
        4,
      ]);
      expect(
        await File(p.join(restored.path, 'region', 'r.0.0.mca')).readAsString(),
        'chunks',
      );
    },
  );

  test('restoring twice is refused instead of overwriting', () async {
    final world = await makeWorld('Survival');
    final backups = Directory(p.join(tmp.path, 'backups'));
    const service = WorldBackupService();
    final backup = await service.backUp(world, backupsDir: backups);

    await service.restore(
      backup.file,
      savesDir: Directory(p.join(tmp.path, 'saves')),
    );
    // The original world is still there, and a second restore of the same archive must
    // not quietly replace anything.
    await expectLater(
      service.restore(
        backup.file,
        savesDir: Directory(p.join(tmp.path, 'saves')),
      ),
      throwsArgumentError,
    );
    expect(
      File(p.join(tmp.path, 'saves', 'Survival', 'level.dat')).existsSync(),
      isTrue,
    );
  });

  test(
    'backing up a world that is gone fails instead of writing an empty zip',
    () async {
      const service = WorldBackupService();
      await expectLater(
        service.backUp(
          Directory(p.join(tmp.path, 'saves', 'Missing')),
          backupsDir: Directory(p.join(tmp.path, 'backups')),
        ),
        throwsArgumentError,
      );
    },
  );

  test('the newest backup is listed first', () async {
    final world = await makeWorld('Survival');
    final backups = Directory(p.join(tmp.path, 'backups'));
    const service = WorldBackupService();
    await service.backUp(world, backupsDir: backups);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final second = await service.backUp(world, backupsDir: backups);

    final listed = await service.listBackups(backups);

    expect(listed.length, 2);
    expect(listed.first.path, second.file.path);
  });
}
