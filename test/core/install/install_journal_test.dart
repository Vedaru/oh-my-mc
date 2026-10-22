import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/install/install_journal.dart';
import 'package:oh_my_mc/core/mc/install_plan.dart';

void main() {
  late Directory root;
  late GamePaths paths;

  setUp(() {
    root = Directory.systemTemp.createTempSync('journal');
    paths = GamePaths(root.path);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('begin marks, finish clears', () async {
    expect(InstallJournal.isIncomplete(paths, '1.20.1'), isFalse);

    await InstallJournal.begin(paths, '1.20.1', stage: 'download');
    expect(InstallJournal.isIncomplete(paths, '1.20.1'), isTrue);

    await InstallJournal.finish(paths, '1.20.1');
    expect(InstallJournal.isIncomplete(paths, '1.20.1'), isFalse);
  });

  test('the marker lives inside the version directory', () async {
    await InstallJournal.begin(paths, '1.20.1');

    // Inside, so it travels with a copied install and disappears with a deleted
    // one; hidden, so it never shows up in a file manager listing by accident.
    expect(
      InstallJournal.markerAt(paths, '1.20.1').path,
      '${paths.versionDir('1.20.1')}/.installing',
    );
  });

  test('it records when the install started', () async {
    final before = DateTime.now().toUtc();
    await InstallJournal.begin(paths, '26.3', stage: 'download');

    final started = InstallJournal.startedAt(paths, '26.3');
    expect(started, isNotNull);
    expect(
      started!.isBefore(before.subtract(const Duration(minutes: 1))),
      isFalse,
    );
    final decoded = jsonDecode(
      InstallJournal.markerAt(paths, '26.3').readAsStringSync(),
    ) as Map;
    expect(decoded['stage'], 'download');
  });

  test('a truncated marker is still a marker', () async {
    final marker = InstallJournal.markerAt(paths, '26.3');
    marker.parent.createSync(recursive: true);
    marker.writeAsStringSync('{"versionId": "26');

    expect(InstallJournal.isIncomplete(paths, '26.3'), isTrue);
    expect(InstallJournal.startedAt(paths, '26.3'), isNull);
  });

  test('finishing an install that never started is not an error', () async {
    await InstallJournal.finish(paths, 'nothing');
    expect(InstallJournal.isIncomplete(paths, 'nothing'), isFalse);
  });
}
