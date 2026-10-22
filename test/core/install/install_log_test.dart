import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/install/install_log.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('install-log'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('lines are timestamped and kept in order', () {
    final log = InstallLog();

    log.add('install started: 26.3', at: DateTime(2026, 10, 22, 21, 4, 51));
    log.add('download [6/9] 12/67 files', at: DateTime(2026, 10, 22, 21, 5));

    expect(log.lines, [
      '21:04:51  install started: 26.3',
      '21:05:00  download [6/9] 12/67 files',
    ]);
  });

  test('the ring drops the oldest lines, not the newest', () {
    final log = InstallLog(capacity: 3);
    for (var i = 0; i < 10; i++) {
      log.add('line $i');
    }

    // The interesting lines of an install are always the last ones.
    expect(log.lines.map((l) => l.substring(10)), [
      'line 7',
      'line 8',
      'line 9',
    ]);
  });

  test('it appends to the file, so a restart can still read it', () {
    final file = File('${tmp.path}/logs/install.log');
    InstallLog(file: file).add('install started: 26.3');

    // A second run (a restart) opens the same file and continues it.
    InstallLog(file: file).add('resume started: 26.3');

    final lines = InstallLog.readTail(file);
    expect(lines, hasLength(2));
    expect(lines.first, contains('install started'));
    expect(lines.last, contains('resume started'));
  });

  test('an unwritable file does not fail the install', () {
    // A directory where the file should be: the append throws, the line survives
    // in memory, and nothing propagates.
    final blocked = Directory('${tmp.path}/blocked.log')
      ..createSync(recursive: true);
    final log = InstallLog(file: File(blocked.path));

    log.add('install started: 26.3');

    expect(log.lines.single, contains('install started'));
  });

  test('readTail of a missing file is empty', () {
    expect(InstallLog.readTail(File('${tmp.path}/nope.log')), isEmpty);
    expect(InstallLog.readTail(File('${tmp.path}/nope.log'), max: 5), isEmpty);
  });

  test('a phase line carries the numbers a reader needs', () {
    expect(
      InstallLog.describePhase(
        'download',
        step: 6,
        steps: 9,
        detail: '26.3',
        bytesDone: 12 * 1024 * 1024,
        bytesTotal: 48 * 1024 * 1024,
      ),
      'download [6/9] 26.3 12.0/48.0 MB',
    );
    // Nothing optional present is still a readable line.
    expect(InstallLog.describePhase('verify'), 'verify');
  });
}
