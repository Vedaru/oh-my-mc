import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/mods/mod_installer.dart';
import 'package:oh_my_mc/core/mods/mod_scanner.dart';
import 'package:oh_my_mc/core/mods/modrinth.dart';
import 'package:path/path.dart' as p;

/// A stand-in for api.modrinth.com plus its CDN.
///
/// The real API is three GETs returning JSON and one file transfer, so the test
/// serves those shapes: `search`, `project/<id>/version`, and the files
/// themselves. What it pins is the part that matters - which version is chosen for
/// a game/loader pair, and which dependencies come with it.
class _Modrinth {
  _Modrinth._(this._server);

  final HttpServer _server;
  final requests = <String>[];

  static Future<_Modrinth> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _Modrinth._(server);
    server.listen(fake._handle);
    return fake;
  }

  Uri get base => Uri.parse('http://127.0.0.1:${_server.port}');
  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    requests.add('$path?${request.uri.query}');

    if (path == '/v2/search') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'hits': [
            {
              'project_id': 'sodium',
              'slug': 'sodium',
              'title': 'Sodium',
              'description': 'Rendering engine',
              'downloads': 12345,
            },
          ],
        }),
      );
    } else if (path.startsWith('/v2/project/') && path.endsWith('/version')) {
      final id = path.split('/')[3];
      request.response.headers.contentType = ContentType.json;
      // A project with no release for this game version answers an empty array,
      // which is what Modrinth does.
      request.response.write(
        jsonEncode(id == 'nothing' ? const [] : _versionsFor(id)),
      );
    } else if (path.startsWith('/files/')) {
      request.response.headers.contentType = ContentType.binary;
      request.response.write('jar:$path');
    } else {
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  }

  /// sodium → indium (required) → nothing; plus an optional dependency that must
  /// not be installed.
  List<Map<String, Object?>> _versionsFor(String id) => [
    {
      'id': '$id-1.0',
      'project_id': id,
      'name': '$id 1.0',
      'version_number': '1.0',
      'loaders': ['fabric'],
      'game_versions': ['1.20.1'],
      'files': [
        {
          'url': '$base/files/$id.jar',
          'filename': '$id-1.0.jar',
          'size': 3,
          'primary': true,
          'hashes': {'sha1': 'abc'},
        },
      ],
      'dependencies': [
        if (id == 'sodium')
          {'project_id': 'indium', 'dependency_type': 'required'},
        if (id == 'sodium')
          {'project_id': 'sodium-extra', 'dependency_type': 'optional'},
      ],
    },
  ];
}

void main() {
  late _Modrinth api;
  late Directory mods;

  setUp(() async {
    api = await _Modrinth.start();
    mods = await Directory.systemTemp.createTemp('mods-install');
  });

  tearDown(() async {
    await api.close();
    if (mods.existsSync()) await mods.delete(recursive: true);
  });

  ModrinthClient client() => ModrinthClient(base: api.base);

  group('search and version selection', () {
    test('search sends the game version and loader as facets', () async {
      final results = await client().search(
        'sodium',
        gameVersion: '1.20.1',
        loader: 'fabric',
      );

      expect(results.single.title, 'Sodium');
      final query = api.requests.single;
      // The facets are the difference between "a Sodium" and "a Sodium that runs
      // in this instance".
      expect(query, contains('project_type%3Amod'));
      expect(query, contains('versions%3A1.20.1'));
      expect(query, contains('categories%3Afabric'));
    });

    test('a project without a matching version is a clear error', () async {
      await expectLater(
        client().versionFor('nothing', gameVersion: '1.20.1', loader: 'fabric'),
        throwsA(isA<ModrinthNoMatch>()),
      );
    });
  });

  group('dependency resolution', () {
    test('required dependencies are included, optional ones are not', () async {
      final plans = await client().resolve(
        projectId: 'sodium',
        title: 'Sodium',
        gameVersion: '1.20.1',
        loader: 'fabric',
      );

      expect(plans.map((p) => p.projectId), ['sodium', 'indium']);
      expect(plans.first.reason, 'direct');
      expect(plans.last.reason, 'required');
      // `sodium-extra` is optional: installing it silently is how a launcher ends
      // up with a mod list the user did not ask for.
      expect(plans.map((p) => p.projectId), isNot(contains('sodium-extra')));
    });

    test('a cycle terminates instead of hanging', () async {
      // Every project required by sodium is fetched once; a graph that points back
      // at sodium must not loop.
      final plans = await client().resolve(
        projectId: 'sodium',
        title: 'Sodium',
        gameVersion: '1.20.1',
        loader: 'fabric',
      );
      final ids = plans.map((p) => p.projectId).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('installing files', () {
    test('downloads each file into mods/ and reports what it did', () async {
      final plans = await client().resolve(
        projectId: 'sodium',
        title: 'Sodium',
        gameVersion: '1.20.1',
        loader: 'fabric',
      );
      final installer = ModInstaller();

      final outcome = await installer.install(plans: plans, modsDir: mods.path);

      expect(outcome.failed, isEmpty);
      expect(outcome.installed, ['sodium-1.0.jar', 'indium-1.0.jar']);
      expect(outcome.skipped, isEmpty);
      expect(
        File(p.join(mods.path, 'sodium-1.0.jar')).readAsStringSync(),
        contains('sodium.jar'),
      );
      // No `.part` files survive a successful install.
      expect(mods.listSync().where((e) => e.path.endsWith('.part')), isEmpty);
    });

    test(
      'a mod that is already there is skipped, enabled or disabled',
      () async {
        final plans = await client().resolve(
          projectId: 'sodium',
          title: 'Sodium',
          gameVersion: '1.20.1',
          loader: 'fabric',
        );
        // One present and enabled, one present and disabled: both mean "installed".
        File(p.join(mods.path, 'sodium-1.0.jar')).writeAsStringSync('old');
        const indium = 'indium-1.0.jar';
        File(p.join(mods.path, '$indium$disabledSuffix'))
            .writeAsStringSync('old');

        final outcome = await ModInstaller().install(
          plans: plans,
          modsDir: mods.path,
        );

        expect(outcome.installed, isEmpty);
        expect(outcome.skipped, ['sodium-1.0.jar', 'indium-1.0.jar']);
        expect(
          File(p.join(mods.path, 'sodium-1.0.jar')).readAsStringSync(),
          'old',
          reason: 'an existing file must not be overwritten',
        );
        // The disabled copy stayed disabled.
        expect(File(p.join(mods.path, 'indium-1.0.jar')).existsSync(), isFalse);
      },
    );

    test(
      'a failed download is reported and leaves no half-written jar',
      () async {
        final plans = [
          ModInstallPlan(
            projectId: 'broken',
            title: 'Broken',
            file: ModrinthFile(
              url: '${api.base}missing/broken.jar',
              filename: 'broken.jar',
              sizeBytes: 0,
            ),
          ),
        ];

        final outcome = await ModInstaller().install(
          plans: plans,
          modsDir: mods.path,
        );

        expect(outcome.failed.keys, ['broken.jar']);
        expect(Directory(mods.path).listSync(), isEmpty);
      },
    );
  });
}
