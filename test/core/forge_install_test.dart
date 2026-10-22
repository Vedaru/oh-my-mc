import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/core/mc/forge_install.dart';
import 'package:oh_my_mc/core/mc/install_plan.dart';
import 'package:path/path.dart' as p;

/// A stand-in for files.minecraftforge.net, maven.minecraftforge.net and
/// maven.neoforged.net: three GETs serving a promotions map, a maven-metadata.xml
/// and a jar. The test asserts the shapes we depend on, not an HTTP client.
class _ForgeServer {
  _ForgeServer._(this._server);

  final HttpServer _server;
  final requests = <String>[];

  /// Bytes of the "installer jar". Content does not matter: the process is faked.
  static const jarBytes = [0x50, 0x4b, 0x03, 0x04];

  static Future<_ForgeServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final forge = _ForgeServer._(server);
    server.listen(forge._handle);
    return forge;
  }

  Uri get base => Uri.parse('http://127.0.0.1:${_server.port}');
  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    requests.add(path);

    if (path.endsWith('promotions_slim.json')) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'homepage': 'https://files.minecraftforge.net/',
          'promos': {
            '1.20.1-recommended': '47.2.0',
            '1.20.1-latest': '47.3.5',
            '1.19.2-recommended': '43.2.0',
          },
        }),
      );
    } else if (path.endsWith('maven-metadata.xml')) {
      request.response.headers.contentType = ContentType('application', 'xml');
      request.response.write(
        '<metadata><versioning><versions>'
        '<version>20.4.237</version>'
        '<version>21.1.9</version>'
        '<version>21.1.80</version>'
        '<version>21.1.100</version>'
        '</versions></versioning></metadata>',
      );
    } else if (path.endsWith('installer.jar')) {
      request.response.headers.contentType = ContentType.binary;
      request.response.add(jarBytes);
    } else {
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  }
}

void main() {
  group('build selection', () {
    late _ForgeServer server;

    setUp(() async {
      server = await _ForgeServer.start();
    });

    tearDown(() async {
      await server.close();
    });

    ForgeMeta meta() => ForgeMeta(
      forgePromotions: server.base.replace(path: '/promotions_slim.json'),
      forgeMaven: server.base,
      neoForgeMetadata: server.base.replace(path: '/maven-metadata.xml'),
      neoForgeMaven: server.base,
    );

    test('Forge uses "recommended" before "latest"', () async {
      final version = await meta().recommendedVersion(
        LoaderKind.forge,
        '1.20.1',
      );

      // 47.3.5 is newer, but "latest" is a snapshot-ish channel: PCL and the
      // Forge site both default to recommended.
      expect(version, '47.2.0');
    });

    test('Forge falls back to "latest" when nothing is recommended', () async {
      final version = await meta().recommendedVersion(
        LoaderKind.forge,
        '1.19.2',
      );

      expect(version, '43.2.0');
    });

    test('an unsupported game version is a clear error', () async {
      await expectLater(
        meta().recommendedVersion(LoaderKind.forge, '1.7.10'),
        throwsA(isA<StateError>()),
      );
    });

    test('NeoForge picks the newest build of the matching game line', () async {
      // 1.21.1 -> 21.1.x, numerically: 21.1.100 beats 21.1.80 (a string sort would
      // pick 21.1.9).
      expect(
        await meta().recommendedVersion(LoaderKind.neoforge, '1.21.1'),
        '21.1.100',
      );
      expect(
        await meta().recommendedVersion(LoaderKind.neoforge, '1.20.4'),
        '20.4.237',
      );
      // No 21.0.x published: the caller gets a clear error, not a silent null.
      await expectLater(
        meta().recommendedVersion(LoaderKind.neoforge, '1.21'),
        throwsA(isA<StateError>()),
      );
    });

    test('installer urls follow each project\'s maven layout', () {
      final urls = meta();

      expect(
        urls.installerUrl(LoaderKind.forge, '1.20.1', '47.2.0').path,
        '/net/minecraftforge/forge/1.20.1-47.2.0/'
        'forge-1.20.1-47.2.0-installer.jar',
      );
      expect(
        urls.installerUrl(LoaderKind.neoforge, '1.21.1', '21.1.80').path,
        '/net/neoforged/neoforge/21.1.80/neoforge-21.1.80-installer.jar',
      );
      expect(
        () => urls.installerUrl(LoaderKind.fabric, '1.20.1', '0.16.9'),
        throwsArgumentError,
      );
    });

    test('a maven root with a path (NeoForge) keeps that path', () {
      // The real NeoForge repository is `https://maven.neoforged.net/releases`.
      // Building the URL by replacing the path drops `/releases` and 404s, which
      // is what the end-to-end run hit.
      final urls = ForgeMeta(
        neoForgeMaven: Uri.parse('https://maven.neoforged.net/releases'),
      );

      expect(
        urls.installerUrl(LoaderKind.neoforge, '1.21.1', '21.1.80').toString(),
        'https://maven.neoforged.net/releases/net/neoforged/neoforge/21.1.80/'
        'neoforge-21.1.80-installer.jar',
      );
    });

    test('version ids are the directory names the installers write', () {
      expect(
        ForgeMeta.versionId(LoaderKind.forge, '1.20.1', '47.2.0'),
        '1.20.1-forge-47.2.0',
      );
      expect(
        ForgeMeta.versionId(LoaderKind.neoforge, '1.21.1', '21.1.80'),
        'neoforge-21.1.80',
      );
      expect(
        () => ForgeMeta.versionId(LoaderKind.quilt, '1.20.1', '0.20.0'),
        throwsArgumentError,
      );
    });
  });

  group('running the installer', () {
    late _ForgeServer server;
    late Directory root;
    late GamePaths paths;

    setUp(() async {
      server = await _ForgeServer.start();
      root = await Directory.systemTemp.createTemp('forge-install');
      paths = GamePaths(root.path);
    });

    tearDown(() async {
      await server.close();
      if (root.existsSync()) await root.delete(recursive: true);
    });

    ForgeInstaller installer({
      required Future<ProcessResult> Function() run,
      String? installId,
      int exitCode = 0,
      String gameVersion = '1.20.1',
    }) => ForgeInstaller(
      meta: ForgeMeta(
        forgePromotions: server.base.replace(path: '/promotions_slim.json'),
        forgeMaven: server.base,
        neoForgeMetadata: server.base.replace(path: '/maven-metadata.xml'),
        neoForgeMaven: server.base,
      ),
      runner: ({required java, required arguments, required workingDirectory}) async {
        expect(java, '/jdk/bin/java');
        expect(workingDirectory, root.path);
        expect(arguments.first, '-jar');
        expect(arguments.sublist(2), ['--installClient', root.path]);
        // What the real installer does: writes the version JSON into the tree.
        final id =
            installId ??
            ForgeMeta.versionId(LoaderKind.forge, gameVersion, '47.2.0');
        if (exitCode == 0) {
          File(paths.versionJson(id))
            ..parent.createSync(recursive: true)
            ..writeAsStringSync(
              jsonEncode({'id': id, 'inheritsFrom': '1.20.1'}),
            );
        }
        // The injected run() wins when it has something to say about exit codes.
        return run();
      },
      client: HttpClient(),
    );

    void vanillaInstalled() {
      File(paths.versionJson('1.20.1'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{"id":"1.20.1"}');
      File(paths.versionJar('1.20.1'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);
    }

    test(
      'downloads the jar, runs it against the launcher dir, returns the id',
      () async {
        vanillaInstalled();
        final stages = <String>[];

        final id = await installer(run: () async => ProcessResult(0, 0, '', ''))
            .install(
              kind: LoaderKind.forge,
              gameVersion: '1.20.1',
              loaderVersion: '47.2.0',
              paths: paths,
              java: '/jdk/bin/java',
              onStage: stages.add,
            );

        expect(id, '1.20.1-forge-47.2.0');
        expect(stages, ['Forge 47.2.0', 'Forge installer']);
        // The jar landed under the launcher dir, not in a temp folder: the installer
        // resolves its libraries relative to itself.
        final jar = File(
          '${root.path}/installers/1.20.1-forge-47.2.0-installer.jar',
        );
        expect(jar.existsSync(), isTrue);
        expect(jar.readAsBytesSync(), _ForgeServer.jarBytes);
        expect(
          server.requests,
          contains(
            '/net/minecraftforge/forge/1.20.1-47.2.0/'
            'forge-1.20.1-47.2.0-installer.jar',
          ),
        );
      },
    );

    test(
      'writes launcher_profiles.json, which the installer demands',
      () async {
        vanillaInstalled();

        // Found by running the real installer: without this file it prints "you need
        // to run the launcher first" and still exits 0.
        await installer(run: () async => ProcessResult(0, 0, '', '')).install(
          kind: LoaderKind.forge,
          gameVersion: '1.20.1',
          loaderVersion: '47.2.0',
          paths: paths,
          java: '/jdk/bin/java',
        );

        final profiles = File('${root.path}/launcher_profiles.json');
        expect(profiles.existsSync(), isTrue);
        final decoded = jsonDecode(profiles.readAsStringSync()) as Map;
        expect(decoded['profiles'], isEmpty);
        expect(decoded['version'], 3);
      },
    );

    test('an existing launcher_profiles.json is left alone', () async {
      vanillaInstalled();
      final profiles = File('${root.path}/launcher_profiles.json')
        ..writeAsStringSync('{"profiles":{"minecraft":{"name":"keep me"}}}');

      await installer(run: () async => ProcessResult(0, 0, '', '')).install(
        kind: LoaderKind.forge,
        gameVersion: '1.20.1',
        loaderVersion: '47.2.0',
        paths: paths,
        java: '/jdk/bin/java',
      );

      // A game directory shared with another launcher keeps that launcher's
      // profiles: this is a launcher's own file, not ours to reset.
      expect(profiles.readAsStringSync(), contains('keep me'));
    });

    test('refuses to run before the vanilla client exists', () async {
      // No versions/1.20.1/1.20.1.jar: the installer would patch nothing.
      await expectLater(
        installer(run: () async => ProcessResult(0, 0, '', '')).install(
          kind: LoaderKind.forge,
          gameVersion: '1.20.1',
          loaderVersion: '47.2.0',
          paths: paths,
          java: '/jdk/bin/java',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('install 1.20.1 before'),
          ),
        ),
      );
      // Not even the jar was fetched: the precondition is checked first.
      expect(server.requests, isEmpty);
    });

    test(
      'a non-zero exit reports the tail of the output, not the banner',
      () async {
        vanillaInstalled();

        await expectLater(
          installer(
            run: () async => ProcessResult(
              0,
              1,
              'Forge installer 47.2.0\nPreparing...\n',
              'Exception in thread "main"\njava.lang.IllegalStateException: no jvm\n',
            ),
          ).install(
            kind: LoaderKind.forge,
            gameVersion: '1.20.1',
            loaderVersion: '47.2.0',
            paths: paths,
            java: '/jdk/bin/java',
          ),
          throwsA(
            isA<StateError>()
                .having((e) => e.message, 'message', contains('exited 1'))
                .having(
                  (e) => e.message,
                  'message',
                  contains('IllegalStateException: no jvm'),
                ),
          ),
        );
      },
    );

    test('exit 0 without a version JSON is still a failure', () async {
      vanillaInstalled();

      await expectLater(
        // Success code, but nothing written: the install did not happen.
        ForgeInstaller(
          meta: ForgeMeta(
            forgePromotions: server.base.replace(path: '/promotions_slim.json'),
            forgeMaven: server.base,
          ),
          runner: ({
            required java,
            required arguments,
            required workingDirectory,
          }) async => ProcessResult(0, 0, 'done!\n', ''),
        ).install(
          kind: LoaderKind.forge,
          gameVersion: '1.20.1',
          loaderVersion: '47.2.0',
          paths: paths,
          java: '/jdk/bin/java',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('wrote no versions/1.20.1-forge-47.2.0/'),
          ),
        ),
      );
    });

    test('NeoForge installs into its own id', () async {
      // NeoForge's game version, installed first like every installer path.
      File(paths.versionJson('1.21.1'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{"id":"1.21.1"}');
      File(paths.versionJar('1.21.1'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);

      final id =
          await installer(
            run: () async => ProcessResult(0, 0, '', ''),
            installId: 'neoforge-21.1.80',
          ).install(
            kind: LoaderKind.neoforge,
            gameVersion: '1.21.1',
            loaderVersion: '21.1.80',
            paths: paths,
            java: '/jdk/bin/java',
          );

      expect(id, 'neoforge-21.1.80');
      expect(
        File(p.join(root.path, 'installers', 'neoforge-21.1.80-installer.jar'))
            .existsSync(),
        isTrue,
      );
    });
  });
}
