import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/logs/log_files.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('log-files'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File write(String name, List<String> lines, {DateTime? modified}) {
    final file = File(p.join(dir.path, name))
      ..writeAsStringSync(lines.map((l) => '$l\n').join());
    if (modified != null) file.setLastModifiedSync(modified);
    return file;
  }

  group('listing', () {
    test('sessions are newest first, install.log is one entry', () async {
      final old = DateTime(2026, 10, 20, 18, 4);
      final recent = DateTime(2026, 10, 22, 23, 58);
      write('launch-2026-10-20T18-04-00-1.19.2.log', ['old'], modified: old);
      write('launch-2026-10-22T23-58-14-26.3.log', ['new'], modified: recent);
      write('install.log', ['install'], modified: DateTime(2026, 10, 21));
      // Not a log: ignored rather than listed as a broken session.
      write('notes.txt', ['hello']);

      final files = await listLogFiles(dir);

      expect(files, hasLength(3));
      expect(files.first.label, '26.3 · 23:58');
      expect(files[1].isInstall, isTrue);
      expect(files.last.label, '1.19.2 · 18:04');
    });

    test('a missing directory is empty, not an error', () async {
      expect(await listLogFiles(Directory(p.join(dir.path, 'nope'))), isEmpty);
    });

    test('an unparseable name still gets a label', () async {
      write('launch-weird.log', ['x']);

      final files = await listLogFiles(dir);

      // Better a raw name than a blank row.
      expect(files.single.label, isNotEmpty);
    });
  });

  group('tail', () {
    test('stderr lines come back marked, so the filter still works', () async {
      final file = write('launch-x.log', [
        'stdout one',
        '! java.lang.RuntimeException: boom',
        'stdout two',
      ]);

      final lines = await readLogTail(file);

      expect(lines.map((l) => l.text), [
        'stdout one',
        'java.lang.RuntimeException: boom',
        'stdout two',
      ]);
      expect(lines[1].isStderr, isTrue);
      expect(lines[0].isStderr, isFalse);
    });

    test('only the last N lines are read', () async {
      final file = write('big.log', [for (var i = 0; i < 50; i++) 'line $i']);

      final lines = await readLogTail(file, max: 5);

      expect(lines, hasLength(5));
      expect(lines.first.text, 'line 45');
      expect(lines.last.text, 'line 49');
    });

    test('a missing file is empty', () async {
      expect(await readLogTail(File(p.join(dir.path, 'nope.log'))), isEmpty);
    });
  });
}
