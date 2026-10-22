import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:oh_my_mc/core/install/version_installer.dart';
import 'package:oh_my_mc/core/net/mirror.dart';
import 'package:oh_my_mc/core/net/version_manifest.dart';

String sha1Of(List<int> bytes) => sha1.convert(bytes).toString();

/// A tiny served Minecraft "world": one manifest, one version, one client jar.
///
/// A real `HttpServer` rather than a mocked client, because the thing under test
/// is our own pipeline: the downloader's `.part` staging, the installer's phase
/// ordering and the controller's event handling all run for real. Mocking the
/// HTTP layer would test the mock.
class MiniWorld {
  MiniWorld._(this._server);

  static Future<MiniWorld> start({bool failEverything = false}) async {
    final world = MiniWorld._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    world.failEverything = failEverything;
    world._server.listen(world._handle);
    return world;
  }

  final HttpServer _server;
  bool failEverything = false;

  /// Set to a completer the handler awaits, so a test can hold a response open
  /// and cancel against a transfer that is genuinely in flight.
  Future<void>? stall;

  final Map<String, List<int>> files = {};

  int get port => _server.port;
  Uri url(String path) => Uri.parse('http://127.0.0.1:$port$path');

  String put(String path, List<int> bytes) {
    files[path] = bytes;
    return url(path).toString();
  }

  Future<void> _handle(HttpRequest request) async {
    final stall = this.stall;
    if (stall != null) await stall;
    final bytes = files[request.uri.path];
    if (failEverything || bytes == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    request.response.add(bytes);
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);

  /// Writes a manifest and one installable vanilla version into [files].
  Future<void> publishVersion(String id) async {
    final clientJar = utf8.encode('client-jar-bytes');
    final clientUrl = put('/version/$id/client.jar', clientJar);

    final versionJson = utf8.encode(
      jsonEncode({
        'id': id,
        'type': 'release',
        'mainClass': 'net.minecraft.client.main.Main',
        'libraries': <Object>[],
        'downloads': {
          'client': {
            'sha1': sha1Of(clientJar),
            'size': clientJar.length,
            'url': clientUrl,
          },
        },
      }),
    );
    final versionUrl = put('/v1/packages/$id/$id.json', versionJson);

    put(
      '/mc/game/version_manifest_v2.json',
      utf8.encode(
        jsonEncode({
          'latest': {'release': id, 'snapshot': id},
          'versions': [
            {
              'id': id,
              'type': 'release',
              'url': versionUrl,
              'sha1': sha1Of(versionJson),
              'releaseTime': '2024-01-01T00:00:00+00:00',
            },
          ],
        }),
      ),
    );
  }

  /// An installer wired to this world, never touching a real host.
  VersionInstaller installer(File cacheFile) => VersionInstaller(
    client: HttpClient(),
    mirrors: MirrorChain(order: const [DownloadSource.official]),
    manifestService: VersionManifestService(
      cacheFile: cacheFile,
      client: HttpClient(),
      mirrors: MirrorChain(order: const [DownloadSource.official]),
      manifestUri: url('/mc/game/version_manifest_v2.json'),
    ),
  );
}
