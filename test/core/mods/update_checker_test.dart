import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/mods/mod_scanner.dart';
import 'package:oh_my_mc/core/mods/modrinth.dart';
import 'package:oh_my_mc/core/mods/update_checker.dart';
import 'package:oh_my_mc/core/net/cancellation.dart';

/// A client where the installed version is looked up by hash and the newest version by
/// project - the two calls an update check makes.
class _Client implements ModrinthClient {
  _Client({required this.newestId});

  final String newestId;
  final asked = <String>[];

  @override
  Future<ModrinthVersion> versionForFile(
    String sha1, {
    CancelToken? cancel,
  }) async {
    asked.add('file:$sha1');
    if (sha1 == 'unknown') throw StateError('no match');
    return const ModrinthVersion(
      id: 'v1',
      projectId: 'p1',
      name: 'Example 1.0',
      versionNumber: '1.0',
      files: [],
      dependencies: [],
    );
  }

  @override
  Future<ModrinthVersion> versionFor(
    String projectId, {
    required String gameVersion,
    String? loader,
    String projectType = 'mod',
    CancelToken? cancel,
  }) async {
    asked.add('project:$projectId:$gameVersion');
    return ModrinthVersion(
      id: newestId,
      projectId: projectId,
      name: 'Example',
      versionNumber: newestId == 'v1' ? '1.0' : '2.0',
      files: const [],
      dependencies: const [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ModEntry _mod(String path) => ModEntry(
  path: path,
  enabled: true,
  sizeBytes: 4,
  loader: ModLoaderKind.fabric,
  name: 'Example',
);

void main() {
  Future<String?> hash(File file) async =>
      file.path.contains('unknown') ? 'unknown' : 'sha1';

  test('a newer version is reported, the current one is not', () async {
    final client = _Client(newestId: 'v2');
    final updates = await FileUpdateChecker(
      client,
      hash: hash,
    ).checkMods([_mod('/mods/a.jar')], gameVersion: '1.20.1', loader: 'fabric');

    expect(updates, hasLength(1));
    expect(updates.single.from, '1.0');
    expect(updates.single.to, '2.0');
    // The project lookup carried the instance's game version: an update to a version
    // the instance cannot run is not an update.
    expect(client.asked, contains('project:p1:1.20.1'));
  });

  test('the installed version being newest is not an update', () async {
    final client = _Client(newestId: 'v1');
    final updates = await FileUpdateChecker(
      client,
      hash: hash,
    ).checkMods([_mod('/mods/a.jar')], gameVersion: '1.20.1', loader: 'fabric');

    expect(updates, isEmpty);
  });

  test('a jar Modrinth has never seen is skipped, not an error', () async {
    final client = _Client(newestId: 'v2');
    final updates = await FileUpdateChecker(client, hash: hash).checkMods(
      [_mod('/mods/unknown.jar'), _mod('/mods/a.jar')],
      gameVersion: '1.20.1',
      loader: 'fabric',
    );

    // The unknown jar is skipped and the known one still reports its update: one
    // unidentifiable file must not hide every other mod's update.
    expect(updates, hasLength(1));
    expect(updates.single.path, '/mods/a.jar');
  });

  test('a file that cannot be hashed is skipped', () async {
    final updates = await FileUpdateChecker(
      _Client(newestId: 'v2'),
      hash: (_) async => null,
    ).checkMods([_mod('/mods/a.jar')], gameVersion: '1.20.1');

    expect(updates, isEmpty);
  });
}
