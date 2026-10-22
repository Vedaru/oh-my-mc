import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/core/mc/install_plan.dart';
import 'package:oh_my_mc/core/mc/loader_meta.dart';

/// A local stand-in for meta.fabricmc.net / meta.quiltmc.org.
///
/// The real services are two GETs returning JSON, so the test asserts the shape we
/// depend on (a loader list, and a profile whose `id`/`inheritsFrom` are the ones
/// the installer will look up) rather than mocking an HTTP client.
class _MetaServer {
  _MetaServer._(this._server);

  final HttpServer _server;
  final requests = <String>[];

  /// Set to serve a profile that disagrees with the id we expect.
  var mismatchedId = false;

  static Future<_MetaServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final meta = _MetaServer._(server);
    server.listen(meta._handle);
    return meta;
  }

  Uri get base => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    requests.add(request.uri.path);
    final path = request.uri.path;
    request.response.headers.contentType = ContentType.json;

    if (path == '/v2/versions/loader/1.20.1') {
      request.response.write(
        jsonEncode([
          {'version': '0.16.9', 'stable': true},
          {'version': '0.16.8', 'stable': true},
        ]),
      );
    } else if (path == '/v2/versions/loader/1.20.1/0.16.9/profile/json') {
      request.response.write(
        jsonEncode({
          'id': mismatchedId
              ? 'fabric-loader-0.16.9-1.21'
              : 'fabric-loader-0.16.9-1.20.1',
          'inheritsFrom': '1.20.1',
          'mainClass': 'net.fabricmc.loader.impl.launch.knot.KnotClient',
          'libraries': [
            {
              'name': 'net.fabricmc:fabric-loader:0.16.9',
              'url': 'https://maven.fabricmc.net/',
            },
          ],
        }),
      );
    } else {
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  }
}

void main() {
  late _MetaServer server;
  late LoaderMeta meta;

  setUp(() async {
    server = await _MetaServer.start();
    meta = LoaderMeta(
      hosts: {LoaderKind.fabric: server.base, LoaderKind.quilt: server.base},
    );
  });

  tearDown(() async {
    meta.close();
    await server.close();
  });

  group('profile ids', () {
    test('follow the id the meta service itself uses', () {
      expect(
        LoaderMeta.profileId(LoaderKind.fabric, '1.20.1', '0.16.9'),
        'fabric-loader-0.16.9-1.20.1',
      );
      expect(
        LoaderMeta.profileId(LoaderKind.quilt, '1.20.1', '0.24.0'),
        'quilt-loader-0.24.0-1.20.1',
      );
    });

    test('parse back to the game version', () {
      expect(LoaderMeta.gameVersionOf('fabric-loader-0.16.9-1.20.1'), '1.20.1');
      // A snapshot id contains dashes of its own, and must survive.
      expect(LoaderMeta.gameVersionOf('fabric-loader-0.16.9-24w14a'), '24w14a');
      expect(LoaderMeta.gameVersionOf('1.20.1'), isNull);
      expect(LoaderMeta.gameVersionOf('not-a-loader'), isNull);
    });
  });

  test('loader versions are listed newest first', () async {
    final versions = await meta.loaderVersions(LoaderKind.fabric, '1.20.1');

    expect(versions, ['0.16.9', '0.16.8']);
    expect(server.requests.single, '/v2/versions/loader/1.20.1');
  });

  group('loader profile', () {
    test('is validated against the id the installer will look up', () async {
      final profile = await meta.loaderProfile(
        LoaderKind.fabric,
        '1.20.1',
        '0.16.9',
      );

      expect(profile['id'], 'fabric-loader-0.16.9-1.20.1');
      expect(profile['inheritsFrom'], '1.20.1');
    });

    test(
      'a renamed id is an error, not a silently unlaunchable install',
      () async {
        server.mismatchedId = true;

        await expectLater(
          meta.loaderProfile(LoaderKind.fabric, '1.20.1', '0.16.9'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('is not "fabric-loader-0.16.9-1.20.1"'),
            ),
          ),
        );
      },
    );

    test('a loader with no meta host is reported, not guessed', () {
      expect(
        () =>
            LoaderMeta(hosts: const {})
                .loaderVersions(LoaderKind.forge, '1.20.1'),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  test(
    'preparing a profile writes the version JSON the installer reads',
    () async {
      final tmp = await Directory.systemTemp.createTemp('loader-profile');
      addTearDown(() async {
        if (tmp.existsSync()) await tmp.delete(recursive: true);
      });
      final paths = GamePaths(tmp.path);

      final id = await LoaderProfileWriter(meta).prepare(
        kind: LoaderKind.fabric,
        gameVersion: '1.20.1',
        loaderVersion: '0.16.9',
        paths: paths,
      );

      expect(id, 'fabric-loader-0.16.9-1.20.1');
      final written = File(paths.versionJson(id));
      expect(written.existsSync(), isTrue);
      final json =
          jsonDecode(await written.readAsString()) as Map<String, Object?>;
      expect(json['inheritsFrom'], '1.20.1');
      expect(json['mainClass'], contains('KnotClient'));
    },
  );
}
