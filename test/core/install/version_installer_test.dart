import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/install/version_installer.dart';
import 'package:oh_my_mc/core/mc/host.dart';
import 'package:oh_my_mc/core/mc/install_plan.dart';
import 'package:oh_my_mc/core/net/cancellation.dart';
import 'package:oh_my_mc/core/net/mirror.dart';
import 'package:oh_my_mc/core/net/version_manifest.dart';

/// A served file: bytes plus the hash Mojang metadata would declare.
class Served {
  Served(this.bytes);

  final List<int> bytes;

  String get sha1 => sha1Of(bytes);
  int get size => bytes.length;
}

String sha1Of(List<int> bytes) => sha1.convert(bytes).toString();

/// Builds a natives zip in memory.
List<int> nativesZip(Map<String, String> files) {
  final archive = Archive();
  for (final e in files.entries) {
    final bytes = utf8.encode(e.value);
    archive.addFile(ArchiveFile(e.key, bytes.length, bytes));
  }
  return ZipEncoder().encode(archive);
}

/// A synthetic version chain exercising natives *and* virtual assets together.
///
/// No real version has both: 1.12.2 ships natives, 1.6.4 ships a `virtual`
/// asset index. The merge is the point of the fixture.
class SyntheticWorld {
  SyntheticWorld._(this._server);

  static Future<SyntheticWorld> start() async {
    final world = SyntheticWorld._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    world._server.listen(world._handle);
    return world;
  }

  final HttpServer _server;

  /// path -> file
  final Map<String, Served> files = {};

  /// Serve this path as a 404 even though [files] has it.
  final Set<String> missing = {};

  final Map<String, int> hits = {};

  /// Highest number of requests in flight at once, to prove concurrency.
  int maxInFlight = 0;
  int _inFlight = 0;

  /// Artificial delay per response, so concurrency is observable.
  Duration delay = Duration.zero;

  int get port => _server.port;
  Uri url(String path) => Uri.parse('http://127.0.0.1:$port$path');

  /// Serves [bytes] at [path] and returns the absolute URL as a string, because
  /// the fixture embeds it in metadata JSON.
  String put(String path, List<int> bytes) {
    files[path] = Served(bytes);
    return url(path).toString();
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    hits[path] = (hits[path] ?? 0) + 1;
    _inFlight++;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    try {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      final served = missing.contains(path) ? null : files[path];
      if (served == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      request.response.headers.contentLength = served.bytes.length;
      request.response.add(served.bytes);
      await request.response.close();
    } finally {
      _inFlight--;
    }
  }

  Future<void> stop() => _server.close(force: true);
}

/// The synthetic metadata, wired to the server.
class Fixture {
  Fixture(this.world, this.paths);

  final SyntheticWorld world;
  final GamePaths paths;

  /// Fixed ids so a rebuild (the concurrency test re-serves the index) does not
  /// trip `late final` twice.
  static const _parentId = '1.6.4-synthetic';
  static const _childId = '1.6.4-forge-synthetic';
  static const _assetIndexId = 'legacy-virtual';

  String get parentId => _parentId;
  String get childId => _childId;
  String get assetIndexId => _assetIndexId;

  late List<String> blobHashes;
  late Map<String, String> virtualNames;

  /// Writes a manifest + a two-level chain (child `inheritsFrom` parent) where
  /// the child adds a modloader-style library and the parent carries natives and
  /// a virtual asset index.
  Future<void> build() async {
    final nativesBytes = nativesZip({
      'liblwjgl.so': 'native-lwjgl',
      'META-INF/MANIFEST.MF': 'should be excluded',
    });
    final nativesServed = world.put(
      '/libraries/org/lwjgl/lwjgl-platform/2.9.0/'
      'lwjgl-platform-2.9.0-natives-linux.jar',
      nativesBytes,
    );

    final libBytes = utf8.encode('library-jar');
    final libServed = world.put(
      '/libraries/com/example/lib/1.0/lib-1.0.jar',
      libBytes,
    );

    final childLibBytes = utf8.encode('patched-jar');
    final childLibServed = world.put(
      '/libraries/com/example/lib/1.0/lib-1.0-forge.jar',
      childLibBytes,
    );

    final jarBytes = utf8.encode('client-jar-bytes');
    final jarServed = world.put('/versions/$parentId/$parentId.jar', jarBytes);

    // Two blobs, one shared between two resource names.
    final blobA = utf8.encode('sound-a');
    final blobB = utf8.encode('sound-b');
    blobHashes = [sha1Of(blobA), sha1Of(blobB)];
    world.put(
      '/assets/${blobA.isEmpty ? '' : blobHashes[0].substring(0, 2)}/'
      '${blobHashes[0]}',
      blobA,
    );
    world.put(
      '/assets/${blobHashes[1].substring(0, 2)}/${blobHashes[1]}',
      blobB,
    );
    virtualNames = {
      'minecraft/sounds/a.ogg': blobHashes[0],
      'minecraft/sounds/a-copy.ogg': blobHashes[0],
      'minecraft/sounds/b.ogg': blobHashes[1],
    };

    final indexJson = utf8.encode(
      jsonEncode({
        'virtual': true,
        'objects': {
          for (final e in virtualNames.entries)
            e.key: {'hash': e.value, 'size': 7},
        },
      }),
    );
    final indexServed = world.put(
      '/assets/indexes/$assetIndexId.json',
      indexJson,
    );

    final parent = {
      'id': parentId,
      'type': 'release',
      'mainClass': 'net.minecraft.client.main.Main',
      'assets': assetIndexId,
      'assetIndex': {
        'id': assetIndexId,
        'url': indexServed,
        'sha1': sha1Of(indexJson),
        'size': indexJson.length,
        'totalSize': 14,
      },
      'downloads': {
        'client': {
          'path': '$parentId.jar',
          'url': jarServed,
          'sha1': sha1Of(jarBytes),
          'size': jarBytes.length,
        },
      },
      'libraries': [
        {
          'name': 'com.example:lib:1.0',
          'downloads': {
            'artifact': {
              'path': 'com/example/lib/1.0/lib-1.0.jar',
              'url': libServed,
              'sha1': sha1Of(libBytes),
              'size': libBytes.length,
            },
          },
        },
        {
          'name': 'org.lwjgl.lwjgl:lwjgl-platform:2.9.0',
          'natives': {'linux': 'natives-linux', 'windows': 'natives-windows'},
          'extract': {
            'exclude': ['META-INF/'],
          },
          'downloads': {
            'classifiers': {
              'natives-linux': {
                'path':
                    'org/lwjgl/lwjgl-platform/2.9.0/'
                    'lwjgl-platform-2.9.0-natives-linux.jar',
                'url': nativesServed,
                'sha1': sha1Of(nativesBytes),
                'size': nativesBytes.length,
              },
            },
          },
        },
        {
          // Excluded on Linux, so it must not be downloaded at all.
          'name': 'com.example:windows-only:1.0',
          'rules': [
            {
              'action': 'allow',
              'os': {'name': 'windows'},
            },
          ],
          'downloads': {
            'artifact': {
              'path': 'com/example/windows-only/1.0/windows-only-1.0.jar',
              'url':
                  '${world.url('/libraries/com/example/windows-only/1.0/'
                  'windows-only-1.0.jar')}',
              'sha1': 'deadbeef',
              'size': 3,
            },
          },
        },
      ],
    };

    final child = {
      'id': childId,
      'type': 'release',
      'inheritsFrom': parentId,
      'mainClass': 'net.minecraft.launchwrapper.Launch',
      'libraries': [
        {
          'name': 'com.example:lib:1.0:forge',
          'downloads': {
            'artifact': {
              'path': 'com/example/lib/1.0/lib-1.0-forge.jar',
              'url': childLibServed,
              'sha1': sha1Of(childLibBytes),
              'size': childLibBytes.length,
            },
          },
        },
      ],
    };

    final childJson = utf8.encode(jsonEncode(child));
    final parentJson = utf8.encode(jsonEncode(parent));
    final childServed = world.put(
      '/v1/packages/child/$childId.json',
      childJson,
    );
    final parentServed = world.put(
      '/v1/packages/parent/$parentId.json',
      parentJson,
    );

    final manifestJson = utf8.encode(
      jsonEncode({
        'latest': {'release': childId, 'snapshot': childId},
        'versions': [
          {
            'id': childId,
            'type': 'release',
            'url': childServed,
            'sha1': sha1Of(childJson),
            'releaseTime': '2024-01-01T00:00:00+00:00',
          },
          {
            'id': parentId,
            'type': 'release',
            'url': parentServed,
            'sha1': sha1Of(parentJson),
            'releaseTime': '2023-01-01T00:00:00+00:00',
          },
        ],
      }),
    );
    world.put('/mc/game/version_manifest_v2.json', manifestJson);
  }

  /// Base URL the installer must use for asset blobs, so nothing reaches out to
  /// `resources.download.minecraft.net`.
  String get assetBase => 'http://127.0.0.1:${world.port}/assets';

  /// An installer pointed at the fake world.
  VersionInstaller installer({HttpClient? client, int concurrency = 4}) {
    final c = client ?? HttpClient();
    return VersionInstaller(
      client: c,
      concurrency: concurrency,
      manifestService: VersionManifestService(
        cacheFile: File('${paths.root}/manifest-cache.json'),
        client: c,
        mirrors: MirrorChain(),
        manifestUri: world.url('/mc/game/version_manifest_v2.json'),
      ),
    );
  }

  static const host = RuleContext(os: HostOs.linux, arch: HostArch.x86_64);
}

void main() {
  late SyntheticWorld world;
  late Directory tmp;
  late GamePaths paths;
  late Fixture fixture;

  setUp(() async {
    world = await SyntheticWorld.start();
    tmp = await Directory.systemTemp.createTemp('installer_test');
    paths = GamePaths(tmp.path);
    fixture = Fixture(world, paths);
    await fixture.build();
  });

  tearDown(() async {
    await world.stop();
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  group('full install', () {
    test('writes the whole tree and verifies clean', () async {
      final installer = fixture.installer();
      final result = await installer.install(
        versionId: fixture.childId,
        paths: paths,
        host: Fixture.host,
        assetBaseUrl: fixture.assetBase,
      );
      installer.close();

      // Metadata: child and parent both persisted where a launch will look.
      expect(File(paths.versionJson(fixture.childId)).existsSync(), isTrue);
      expect(File(paths.versionJson(fixture.parentId)).existsSync(), isTrue);

      // The client jar is inherited from the parent but written under the
      // child's directory, because the child declares no `jar` override. A
      // Forge profile that sets `jar` would write it under the parent instead.
      expect(
        File(paths.versionJar(fixture.childId)).readAsStringSync(),
        'client-jar-bytes',
      );

      // Both the parent library and the child's patched build are present.
      expect(
        File(paths.libraryFile('com/example/lib/1.0/lib-1.0.jar'))
            .readAsStringSync(),
        'library-jar',
      );
      expect(
        File(paths.libraryFile('com/example/lib/1.0/lib-1.0-forge.jar'))
            .readAsStringSync(),
        'patched-jar',
      );

      // Rules excluded the Windows-only library, so it was never fetched.
      expect(
        File(
          paths.libraryFile(
            'com/example/windows-only/1.0/windows-only-1.0.jar',
          ),
        ).existsSync(),
        isFalse,
      );
      expect(
        world.hits.containsKey(
          '/libraries/com/example/windows-only/1.0/windows-only-1.0.jar',
        ),
        isFalse,
      );

      // Natives unpacked, META-INF excluded.
      final natives = Directory(paths.natives(fixture.childId));
      expect(
        File('${natives.path}/liblwjgl.so').readAsStringSync(),
        'native-lwjgl',
      );
      expect(
        File('${natives.path}/META-INF/MANIFEST.MF').existsSync(),
        isFalse,
      );

      // Asset objects by hash...
      for (final hash in fixture.blobHashes) {
        expect(File(paths.assetObject(hash)).existsSync(), isTrue);
      }
      // ...and materialized copies for the virtual layout, including the
      // second name that shares one blob.
      final virtualRoot = '${paths.virtualAssets}/${fixture.assetIndexId}';
      expect(
        File('$virtualRoot/minecraft/sounds/a.ogg').readAsStringSync(),
        'sound-a',
      );
      expect(
        File('$virtualRoot/minecraft/sounds/a-copy.ogg').readAsStringSync(),
        'sound-a',
      );
      expect(
        File('$virtualRoot/minecraft/sounds/b.ogg').readAsStringSync(),
        'sound-b',
      );

      expect(result.verification.isComplete, isTrue);
      expect(result.nativesFiles, 1);
      expect(result.assets.copies, 3);
      expect(result.version.mainClass, 'net.minecraft.launchwrapper.Launch');
    });

    test('reports every phase in order', () async {
      final installer = fixture.installer();
      final phases = <InstallPhase>[];
      await installer.install(
        versionId: fixture.childId,
        paths: paths,
        host: Fixture.host,
        assetBaseUrl: fixture.assetBase,
        onProgress: (p) {
          if (phases.isEmpty || phases.last != p.phase) phases.add(p.phase);
        },
      );
      installer.close();

      expect(phases.first, InstallPhase.manifest);
      expect(phases.last, InstallPhase.verify);
      expect(phases, contains(InstallPhase.download));
      expect(phases, contains(InstallPhase.natives));
      expect(phases, contains(InstallPhase.assets));
      expect(
        phases.indexOf(InstallPhase.download),
        lessThan(phases.indexOf(InstallPhase.natives)),
        reason:
            'extraction must follow the download that produced the archives',
      );
    });

    test('a second install fetches nothing again', () async {
      final first = fixture.installer();
      await first.install(
        versionId: fixture.childId,
        paths: paths,
        host: Fixture.host,
        assetBaseUrl: fixture.assetBase,
      );
      first.close();

      final before = Map<String, int>.of(world.hits);
      final second = fixture.installer();
      await second.install(
        versionId: fixture.childId,
        paths: paths,
        host: Fixture.host,
        assetBaseUrl: fixture.assetBase,
      );
      second.close();

      // Manifests may be re-requested (the cache TTL is the launcher's, not the
      // installer's) but no payload may be.
      for (final path in before.keys) {
        if (path.contains('version_manifest')) continue;
        expect(
          world.hits[path],
          before[path],
          reason: '$path was re-downloaded on the second install',
        );
      }
    });
  });

  group('concurrency', () {
    test('fetches files in parallel, bounded by the limit', () async {
      // More assets so parallelism is measurable, and a delay so serial and
      // parallel runs differ observably.
      final extra = <String, List<int>>{};
      for (var i = 0; i < 12; i++) {
        extra['minecraft/sounds/extra$i.ogg'] = utf8.encode('blob$i');
      }
      // Rewrite the index with the extras, keeping the fixture's blobs.
      final indexJson = utf8.encode(
        jsonEncode({
          'virtual': true,
          'objects': {
            for (final e in fixture.virtualNames.entries)
              e.key: {'hash': e.value, 'size': 7},
            for (final e in extra.entries)
              e.key: {'hash': sha1Of(e.value), 'size': e.value.length},
          },
        }),
      );
      for (final e in extra.entries) {
        final hash = sha1Of(e.value);
        world.put('/assets/${hash.substring(0, 2)}/$hash', e.value);
      }
      world.put('/assets/indexes/${fixture.assetIndexId}.json', indexJson);
      // The parent's declared index hash no longer matches, so rebuild it.
      await fixture.build();
      world.delay = const Duration(milliseconds: 40);

      final installer = fixture.installer(concurrency: 4);
      await installer.install(
        versionId: fixture.childId,
        paths: paths,
        host: Fixture.host,
        assetBaseUrl: fixture.assetBase,
      );
      installer.close();

      expect(
        world.maxInFlight,
        greaterThan(1),
        reason: 'the downloader must actually run transfers in parallel',
      );
      expect(
        world.maxInFlight,
        lessThanOrEqualTo(4),
        reason: 'concurrency must be bounded, not unbounded',
      );
    });
  });

  group('cancellation', () {
    test('cancelling during download throws and unpacks no natives', () async {
      world.delay = const Duration(milliseconds: 50);
      final cancel = CancelToken();
      final installer = fixture.installer();
      final future = installer.install(
        versionId: fixture.childId,
        paths: paths,
        host: Fixture.host,
        assetBaseUrl: fixture.assetBase,
        cancel: cancel,
      );
      // Cancel once the pipeline is definitely under way.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      cancel.cancel();

      await expectLater(future, throwsA(isA<CancelledException>()));
      installer.close();

      expect(
        Directory(paths.natives(fixture.childId)).existsSync(),
        isFalse,
        reason: 'no half-unpacked natives after a cancel',
      );
    });

    test('a pre-cancelled token fails before touching the network', () async {
      final cancel = CancelToken()..cancel();
      final installer = fixture.installer();
      await expectLater(
        installer.install(
          versionId: fixture.childId,
          paths: paths,
          host: Fixture.host,
          assetBaseUrl: fixture.assetBase,
          cancel: cancel,
        ),
        throwsA(isA<CancelledException>()),
      );
      installer.close();
      expect(world.hits, isEmpty);
    });
  });

  group('errors', () {
    test('an unknown version names the id', () async {
      final installer = fixture.installer();
      await expectLater(
        installer.install(
          versionId: 'not-a-version',
          paths: paths,
          host: Fixture.host,
          assetBaseUrl: fixture.assetBase,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('not-a-version'),
          ),
        ),
      );
      installer.close();
    });

    test('a 404 on a library fails the install', () async {
      world.missing.add('/libraries/com/example/lib/1.0/lib-1.0.jar');
      final installer = fixture.installer();
      await expectLater(
        installer.install(
          versionId: fixture.childId,
          paths: paths,
          host: Fixture.host,
          assetBaseUrl: fixture.assetBase,
        ),
        throwsA(anything),
      );
      installer.close();
      expect(
        File(paths.libraryFile('com/example/lib/1.0/lib-1.0.jar')).existsSync(),
        isFalse,
      );
    });
  });
}
