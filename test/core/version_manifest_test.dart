import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/net/version_manifest.dart';

import 'fixtures.dart';

/// A URL on a closed port: connecting fails fast, standing in for "offline"
/// without unplugging the sandbox's real network.
Uri deadUri() =>
    Uri.parse('http://127.0.0.1:1/mc/game/version_manifest_v2.json');

void main() {
  group('manifest model', () {
    late final VersionManifest manifest = VersionManifest.fromJson(
      loadJson('version_manifest_v2.json'),
    );

    test('reads latest release and snapshot', () {
      expect(manifest.latestRelease, '26.3');
      expect(manifest.latestSnapshot, isNotEmpty);
      expect(manifest.versions, isNotEmpty);
    });

    test('looks up by id', () {
      final v = manifest.byId('1.20.1');
      expect(v, isNotNull);
      expect(v!.isRelease, isTrue);
      expect(v.url, contains('piston-meta.mojang.com'));
      expect(v.sha1, hasLength(40));
    });

    test('unknown id is null rather than an exception', () {
      expect(manifest.byId('9.9.9'), isNull);
    });

    test('splits releases from snapshots', () {
      expect(manifest.releases.every((v) => v.type == 'release'), isTrue);
      expect(manifest.snapshots.every((v) => v.type == 'snapshot'), isTrue);
    });

    test('groups releases into version lines', () {
      final lines = manifest.byLine;
      expect(lines.keys, contains('1.20'));
      expect(lines['1.20']!.map((v) => v.id), contains('1.20.1'));
    });

    test('ancient versions are flagged', () {
      final beta = ManifestVersion.fromJson(const {
        'id': 'b1.7.3',
        'type': 'old_beta',
        'url': 'https://x/y.json',
        'sha1': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'releaseTime': '2011-07-08T00:00:00+00:00',
      });
      expect(beta.isAncient, isTrue);
      expect(beta.isRelease, isFalse);
    });

    test('round-trips through json', () {
      final restored = VersionManifest.fromJson(manifest.toJson());
      expect(restored.versions.length, manifest.versions.length);
      expect(restored.latestRelease, manifest.latestRelease);
      expect(restored.byId('1.20.1')!.url, manifest.byId('1.20.1')!.url);
    });
  });

  group('VersionManifestService cache', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('manifest_test'));
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('a fresh cache is used without any network access', () async {
      final cacheFile = File('${tmp.path}/manifest.json');
      final source = loadJson('version_manifest_v2.json');
      cacheFile.writeAsStringSync(jsonEncode(source));

      // No server is running, so any network attempt would fail the test.
      final service = VersionManifestService(cacheFile: cacheFile);
      final manifest = await service.load();

      expect(service.servedStale, isFalse);
      expect(manifest.byId('1.20.1'), isNotNull);
      service.close();
    });

    test('a stale cache is still served when the network fails', () async {
      final cacheFile = File('${tmp.path}/manifest.json');
      cacheFile.writeAsStringSync(
        jsonEncode(loadJson('version_manifest_v2.json')),
      );
      // Age the file beyond the TTL.
      cacheFile.setLastModifiedSync(
        DateTime.now().subtract(const Duration(days: 30)),
      );

      final service = VersionManifestService(
        cacheFile: cacheFile,
        ttl: const Duration(hours: 1),
        manifestUri: deadUri(),
      );
      final manifest = await service.load();

      expect(
        service.servedStale,
        isTrue,
        reason: 'offline must not break launch',
      );
      expect(manifest.versions, isNotEmpty);
      service.close();
    });

    test('a corrupt cache is treated as absent', () async {
      final cacheFile = File('${tmp.path}/manifest.json');
      cacheFile.writeAsStringSync('{not json');

      final service = VersionManifestService(
        cacheFile: cacheFile,
        manifestUri: deadUri(),
      );
      await expectLater(service.load(), throwsA(isA<Object>()));
      service.close();
    });

    test('a missing cache and no network throws', () async {
      final service = VersionManifestService(
        cacheFile: File('${tmp.path}/none.json'),
        manifestUri: deadUri(),
      );
      await expectLater(service.load(), throwsA(isA<Object>()));
      service.close();
    });

    test('in-memory result is reused across calls', () async {
      final cacheFile = File('${tmp.path}/manifest.json');
      cacheFile.writeAsStringSync(
        jsonEncode(loadJson('version_manifest_v2.json')),
      );
      final service = VersionManifestService(cacheFile: cacheFile);

      final first = await service.load();
      final second = await service.load();
      expect(identical(first, second), isTrue);
      service.close();
    });
  });
}
