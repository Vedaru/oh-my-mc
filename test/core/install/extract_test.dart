import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/install/extract.dart';
import 'package:oh_my_mc/core/net/cancellation.dart';

/// Builds a zip on disk. Real bytes, not a mock: the decoder is the code under
/// test as much as the extraction loop is.
String writeZip(String path, Map<String, List<int>> entries) {
  final archive = Archive();
  for (final entry in entries.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(ZipEncoder().encode(archive));
  return path;
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('extract_test');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  group('extraction', () {
    test('unpacks files and reports them', () async {
      final zip = writeZip('${tmp.path}/natives.zip', {
        'liblwjgl.so': utf8.encode('so-bytes'),
        'libopenal.so': utf8.encode('openal'),
      });
      final dest = '${tmp.path}/natives';

      final results = await extractNatives(
        archives: [NativeArchiveSpec(file: zip, label: 'lwjgl')],
        destination: dest,
      );

      expect(File('$dest/liblwjgl.so').readAsStringSync(), 'so-bytes');
      expect(File('$dest/libopenal.so').readAsStringSync(), 'openal');
      expect(results.single.entries.length, 2);
      expect(
        Directory('$dest.tmp').existsSync(),
        isFalse,
        reason: 'the staging directory must not survive a success',
      );
    });

    test('honours extract.exclude for a directory prefix', () async {
      final zip = writeZip('${tmp.path}/n.zip', {
        'META-INF/MANIFEST.MF': utf8.encode('manifest'),
        'META-INF/services/thing': utf8.encode('spi'),
        'libfoo.so': utf8.encode('real'),
      });

      await extractNatives(
        archives: [
          NativeArchiveSpec(file: zip, label: 'x', exclude: ['META-INF/']),
        ],
        destination: '${tmp.path}/out',
      );

      expect(File('${tmp.path}/out/libfoo.so').existsSync(), isTrue);
      expect(Directory('${tmp.path}/out/META-INF').existsSync(), isFalse);
    });

    test('exclude is case-insensitive', () async {
      final zip = writeZip('${tmp.path}/n.zip', {
        'meta-inf/MANIFEST.MF': utf8.encode('m'),
        'libfoo.so': utf8.encode('real'),
      });

      await extractNatives(
        archives: [
          NativeArchiveSpec(file: zip, label: 'x', exclude: ['META-INF/']),
        ],
        destination: '${tmp.path}/out',
      );

      expect(Directory('${tmp.path}/out/meta-inf').existsSync(), isFalse);
      expect(File('${tmp.path}/out/libfoo.so').existsSync(), isTrue);
    });

    test('nested directories are created', () async {
      final zip = writeZip('${tmp.path}/n.zip', {
        'a/b/c/deep.so': utf8.encode('deep'),
      });

      await extractNatives(
        archives: [NativeArchiveSpec(file: zip, label: 'x')],
        destination: '${tmp.path}/out',
      );

      expect(File('${tmp.path}/out/a/b/c/deep.so').readAsStringSync(), 'deep');
    });

    test('entries from two archives merge into one directory', () async {
      final first = writeZip('${tmp.path}/one.zip', {
        'liba.so': utf8.encode('a'),
      });
      final second = writeZip('${tmp.path}/two.zip', {
        'libb.so': utf8.encode('b'),
      });

      await extractNatives(
        archives: [
          NativeArchiveSpec(file: first, label: 'one'),
          NativeArchiveSpec(file: second, label: 'two'),
        ],
        destination: '${tmp.path}/merged',
      );

      expect(File('${tmp.path}/merged/liba.so').existsSync(), isTrue);
      expect(File('${tmp.path}/merged/libb.so').existsSync(), isTrue);
    });
  });

  group('path traversal', () {
    test('a ../ entry is refused and nothing is written', () async {
      final zip = writeZip('${tmp.path}/evil.zip', {
        'libfine.so': utf8.encode('ok'),
        '../../escaped.txt': utf8.encode('pwned'),
      });

      await expectLater(
        extractNatives(
          archives: [NativeArchiveSpec(file: zip, label: 'evil')],
          destination: '${tmp.path}/natives',
        ),
        throwsA(isA<FormatException>()),
      );

      expect(
        File('${tmp.path}/escaped.txt').existsSync(),
        isFalse,
        reason: 'traversal must not escape the natives directory',
      );
      expect(
        Directory('${tmp.path}/natives').existsSync(),
        isFalse,
        reason: 'a refused archive must not leave a partial natives dir',
      );
    });

    test('a deeply nested ../ is refused', () async {
      final zip = writeZip('${tmp.path}/evil2.zip', {
        'a/../../../escape.so': utf8.encode('pwned'),
      });

      await expectLater(
        extractNatives(
          archives: [NativeArchiveSpec(file: zip, label: 'evil2')],
          destination: '${tmp.path}/natives',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(Directory('${tmp.path}/natives').existsSync(), isFalse);
    });

    test('an absolute path entry is refused', () async {
      final zip = writeZip('${tmp.path}/evil3.zip', {
        '/tmp/absolute-pwned.so': utf8.encode('pwned'),
      });

      await expectLater(
        extractNatives(
          archives: [NativeArchiveSpec(file: zip, label: 'evil3')],
          destination: '${tmp.path}/natives',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(File('/tmp/absolute-pwned.so').existsSync(), isFalse);
    });

    test('a drive-letter entry is refused', () async {
      expect(
        () => safeRelativeEntryName('C:/Windows/evil.dll', 'x'),
        throwsA(isA<FormatException>()),
      );
    });

    test('backslash traversal is caught, not treated as a filename', () async {
      // A Windows-built zip uses `\`; on Linux `path.normalize` would keep it as
      // one literal filename, so the separator unification is what makes this
      // check meaningful.
      expect(
        () => safeRelativeEntryName(r'..\..\evil.so', 'x'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('atomicity and idempotence', () {
    test('an existing natives dir is replaced, not merged', () async {
      final dest = Directory('${tmp.path}/natives')
        ..createSync(recursive: true);
      File('${dest.path}/stale.so').writeAsStringSync('old');
      final zip = writeZip('${tmp.path}/n.zip', {
        'fresh.so': utf8.encode('new'),
      });

      await extractNatives(
        archives: [NativeArchiveSpec(file: zip, label: 'x')],
        destination: dest.path,
      );

      expect(
        File('${dest.path}/stale.so').existsSync(),
        isFalse,
        reason: 'a reinstall must not leave .so files from a previous version',
      );
      expect(File('${dest.path}/fresh.so').readAsStringSync(), 'new');
    });

    test('running twice produces the same result', () async {
      final zip = writeZip('${tmp.path}/n.zip', {
        'lib.so': utf8.encode('stable'),
      });
      final dest = '${tmp.path}/natives';
      final spec = NativeArchiveSpec(file: zip, label: 'x');

      await extractNatives(archives: [spec], destination: dest);
      await extractNatives(archives: [spec], destination: dest);

      expect(File('$dest/lib.so').readAsStringSync(), 'stable');
      expect(Directory('$dest.tmp').existsSync(), isFalse);
    });

    test('a leftover staging dir from a killed run is discarded', () async {
      final dest = '${tmp.path}/natives';
      Directory('$dest.tmp').createSync(recursive: true);
      File('$dest.tmp/garbage.so').writeAsStringSync('half-written');
      final zip = writeZip('${tmp.path}/n.zip', {'real.so': utf8.encode('ok')});

      await extractNatives(
        archives: [NativeArchiveSpec(file: zip, label: 'x')],
        destination: dest,
      );

      expect(File('$dest/real.so').existsSync(), isTrue);
      expect(File('$dest/garbage.so').existsSync(), isFalse);
    });
  });

  group('cancellation', () {
    test('cancelling before extraction leaves no natives dir', () async {
      final zip = writeZip('${tmp.path}/n.zip', {'lib.so': utf8.encode('x')});
      final cancel = CancelToken()..cancel();

      await expectLater(
        extractNatives(
          archives: [NativeArchiveSpec(file: zip, label: 'x')],
          destination: '${tmp.path}/natives',
          cancel: cancel,
        ),
        throwsA(isA<CancelledException>()),
      );

      expect(Directory('${tmp.path}/natives').existsSync(), isFalse);
      expect(
        Directory('${tmp.path}/natives.tmp').existsSync(),
        isFalse,
        reason: 'a cancelled extraction must not leave staging behind',
      );
    });

    test('out-of-work resources are still cleaned up on cancel', () async {
      final zip = writeZip('${tmp.path}/n.zip', {
        for (var i = 0; i < 50; i++) 'lib$i.so': utf8.encode('x$i'),
      });
      final cancel = CancelToken();
      // Cancel from inside the extraction loop by cancelling on the first tick.
      final future = extractNatives(
        archives: [NativeArchiveSpec(file: zip, label: 'x')],
        destination: '${tmp.path}/natives',
        cancel: cancel,
      );
      cancel.cancel();

      await expectLater(future, throwsA(isA<CancelledException>()));
      expect(Directory('${tmp.path}/natives').existsSync(), isFalse);
      expect(Directory('${tmp.path}/natives.tmp').existsSync(), isFalse);
    });
  });

  group('bad input', () {
    test('a missing archive names the file', () async {
      await expectLater(
        extractNatives(
          archives: [
            NativeArchiveSpec(file: '${tmp.path}/absent.zip', label: 'absent'),
          ],
          destination: '${tmp.path}/natives',
        ),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('a non-zip file is a FormatException, not a crash', () async {
      final fake = File('${tmp.path}/notzip.zip')
        ..writeAsStringSync('this is not a zip at all');

      await expectLater(
        extractNatives(
          archives: [NativeArchiveSpec(file: fake.path, label: 'fake')],
          destination: '${tmp.path}/natives',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('isExcluded', () {
    test('matches a bare name and a prefix with slash', () {
      expect(isExcluded('META-INF', ['META-INF/']), isTrue);
      expect(isExcluded('META-INF/x', ['META-INF']), isTrue);
      expect(isExcluded('META-INFx', ['META-INF']), isFalse);
      expect(isExcluded('lib.so', []), isFalse);
      expect(isExcluded('lib.so', ['META-INF/']), isFalse);
    });
  });
}
