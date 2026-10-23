import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/install/version_remover.dart';
import 'package:path/path.dart' as p;

/// An uninstall deletes that version's own directory and nothing else: `libraries/` and
/// `assets/` are shared, and an instance is the user's, not the installer's.
void main() {
  late Directory tmp;

  setUp(
    () async => tmp = await Directory.systemTemp.createTemp('version-remover'),
  );
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<String> makeVersion(String id) async {
    final versions = p.join(tmp.path, 'versions');
    final dir = Directory(p.join(versions, id));
    await Directory(p.join(dir.path, 'natives')).create(recursive: true);
    await File(p.join(dir.path, '$id.json')).writeAsString('{}');
    await File(p.join(dir.path, '$id.jar')).writeAsBytes([1, 2, 3]);
    return versions;
  }

  test(
    'removes the version directory and leaves the rest of the tree',
    () async {
      final versions = await makeVersion('1.20.1');
      await makeVersion('1.21');
      final libraries = Directory(p.join(tmp.path, 'libraries'))..createSync();
      File(p.join(libraries.path, 'a.jar')).writeAsString('shared');

      final removed = await const VersionRemover().remove(
        '1.20.1',
        versionsDir: versions,
      );

      expect(removed, isTrue);
      expect(Directory(p.join(versions, '1.20.1')).existsSync(), isFalse);
      // The other version and the shared libraries are untouched: deleting those to
      // reclaim space would break every version the user still has.
      expect(Directory(p.join(versions, '1.21')).existsSync(), isTrue);
      expect(File(p.join(libraries.path, 'a.jar')).existsSync(), isTrue);
    },
  );

  test('removing what is not there says so instead of throwing', () async {
    final versions = p.join(tmp.path, 'versions');
    await Directory(versions).create(recursive: true);

    expect(
      await const VersionRemover().remove('nope', versionsDir: versions),
      isFalse,
    );
  });

  test('a version id is a directory name, not a path', () async {
    final versions = await makeVersion('1.20.1');

    for (final bad in ['', '.', '..', '../1.20.1', 'a/b']) {
      await expectLater(
        const VersionRemover().remove(bad, versionsDir: versions),
        throwsArgumentError,
        reason: 'accepted "$bad"',
      );
    }
    // The version is still there after every refused attempt.
    expect(Directory(p.join(versions, '1.20.1')).existsSync(), isTrue);
  });

  test('exists answers for the directory, not the journal', () async {
    final versions = await makeVersion('1.20.1');
    const remover = VersionRemover();

    expect(await remover.exists('1.20.1', versionsDir: versions), isTrue);
    expect(await remover.exists('1.20.2', versionsDir: versions), isFalse);
  });
}
