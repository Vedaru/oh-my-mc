import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/mc/host.dart';
import 'package:oh_my_mc/core/mc/install_plan.dart';
import 'package:oh_my_mc/core/mc/library_graph.dart';
import 'package:oh_my_mc/core/mc/version_json.dart';
import 'package:oh_my_mc/core/net/downloader.dart';

import 'fixtures.dart';

const _linux = RuleContext(os: HostOs.linux, arch: HostArch.x86_64);
const _paths = GamePaths('/mc');

void main() {
  group('GamePaths', () {
    test('matches the vanilla layout', () {
      expect(_paths.versions, '/mc/versions');
      expect(_paths.libraries, '/mc/libraries');
      expect(_paths.assets, '/mc/assets');
      expect(_paths.versionJson('1.20.1'), '/mc/versions/1.20.1/1.20.1.json');
      expect(_paths.versionJar('1.20.1'), '/mc/versions/1.20.1/1.20.1.jar');
      expect(_paths.natives('1.12.2'), '/mc/versions/1.12.2/natives');
    });

    test('asset objects use the two-character shard', () {
      expect(
        _paths.assetObject('abcdef0123456789abcdef0123456789abcdef01'),
        '/mc/assets/objects/ab/abcdef0123456789abcdef0123456789abcdef01',
      );
    });

    test('legacy resources dir is outside assets', () {
      expect(_paths.legacyResources, '/mc/resources');
    });
  });

  group('planInstall (1.20.1, linux)', () {
    late final InstallPlan plan = planInstall(
      version: loadVersion('1.20.1'),
      host: _linux,
      paths: _paths,
      assetIndex: loadAssetIndex('1.20.1'),
    );

    test('includes the client jar, libraries and assets', () {
      expect(plan.fileCount, greaterThan(60));
      expect(plan.totalBytes, greaterThan(50 * 1024 * 1024));
      expect(plan.missingNatives, isEmpty);
      expect(
        plan.stages.keys,
        containsAll([
          InstallStage.versionJson,
          InstallStage.libraries,
          InstallStage.assets,
          InstallStage.logging,
        ]),
      );
    });

    test('client jar targets the version directory', () {
      final client = plan.tasks.firstWhere(
        (t) => t.targetPath.endsWith('1.20.1.jar'),
      );
      expect(client.targetPath, '/mc/versions/1.20.1/1.20.1.jar');
      expect(client.url.host, 'piston-data.mojang.com');
      expect(client.sha1, hasLength(40));
    });

    test('libraries land under libraries/ with their maven path', () {
      final lib = plan.tasks.firstWhere(
        (t) => t.targetPath.contains('/libraries/'),
      );
      expect(lib.targetPath, startsWith('/mc/libraries/'));
      expect(lib.url.host, 'libraries.minecraft.net');
      expect(lib.sha1, hasLength(40));
      expect(lib.size, greaterThan(0));
    });

    test('asset objects dedupe by hash', () {
      final objects = plan.tasks
          .where((t) => t.targetPath.contains('/assets/objects/'))
          .map((t) => t.targetPath)
          .toList();
      expect(objects, isNotEmpty);
      expect(objects.toSet().length, objects.length);
    });

    test('asset index file is planned before objects', () {
      final indexTask = plan.tasks.firstWhere(
        (t) => t.targetPath == '/mc/assets/indexes/5.json',
      );
      expect(indexTask.priority, DownloadPriority.metadata);
      final firstObjectIdx = plan.tasks.indexWhere(
        (t) => t.targetPath.contains('/assets/objects/'),
      );
      expect(
        plan.tasks.indexOf(indexTask),
        lessThan(firstObjectIdx),
        reason: 'index must be planned ahead of the objects it describes',
      );
    });

    test('logging config is included with its own stage', () {
      final log = plan.tasks.firstWhere(
        (t) => t.targetPath.contains('/assets/log_configs/'),
      );
      expect(log.size, greaterThan(0));
      expect(plan.stages[InstallStage.logging], log.size);
    });

    test('every task has an absolute path and a real url', () {
      for (final t in plan.tasks) {
        expect(t.targetPath, startsWith('/mc/'));
        expect(t.url.hasScheme, isTrue);
        expect(t.url.host, isNotEmpty);
      }
    });
  });

  group('planInstall (1.12.2, linux)', () {
    test('includes native archives for the host', () {
      final version = loadVersion('1.12.2');
      final plan = planInstall(
        version: version,
        host: _linux,
        paths: _paths,
        assetIndex: loadAssetIndex('1.12.2'),
      );
      final graph = buildLibraryGraph(version, _linux);

      expect(plan.missingNatives, isEmpty);
      expect(graph.natives, isNotEmpty);
      for (final native in graph.natives) {
        expect(
          plan.tasks.any((t) => t.targetPath.endsWith(native.file.path)),
          isTrue,
          reason: '${native.file.path} missing from the plan',
        );
      }
    });
  });

  group('planInstall (26.3, linux)', () {
    test('has no natives but a much larger library set', () {
      final plan = planInstall(
        version: loadVersion('26.3'),
        host: _linux,
        paths: _paths,
      );
      expect(plan.missingNatives, isEmpty);
      final libraryCount = plan.tasks
          .where((t) => t.targetPath.contains('/libraries/'))
          .length;
      expect(libraryCount, greaterThan(60));
    });

    test('without an asset index the object downloads are simply absent', () {
      final plan = planInstall(
        version: loadVersion('26.3'),
        host: _linux,
        paths: _paths,
      );
      expect(
        plan.tasks.where((t) => t.targetPath.contains('/assets/objects/')),
        isEmpty,
      );
      // The index *file* is still planned: it is what tells us the objects.
      expect(
        plan.tasks.where((t) => t.targetPath.contains('/assets/indexes/')),
        hasLength(1),
      );
    });

    test(
      'includeAssets: false omits indexes and objects but keeps logging',
      () {
        final plan = planInstall(
          version: loadVersion('26.3'),
          host: _linux,
          paths: _paths,
          assetIndex: loadAssetIndex('26.3'),
          includeAssets: false,
        );
        expect(
          plan.tasks.where((t) => t.targetPath.contains('/assets/objects/')),
          isEmpty,
        );
        expect(
          plan.tasks.where((t) => t.targetPath.contains('/assets/indexes/')),
          isEmpty,
        );
        // The log4j config is a launch input, not asset content: it stays.
        expect(
          plan.tasks.where(
            (t) => t.targetPath.contains('/assets/log_configs/'),
          ),
          hasLength(1),
        );
      },
    );
  });

  group('jar override (Forge-style)', () {
    test(
      'a version that reuses its parent jar does not plan a second copy',
      () {
        final base = loadJson('version_1.20.1.json');
        final forge = <String, dynamic>{
          'id': 'forge-test',
          'type': 'release',
          'mainClass': 'cpw.mods.bootstraplauncher.BootstrapLauncher',
          'inheritsFrom': '1.20.1',
          'jar': '1.20.1',
          'libraries': <dynamic>[],
        };
        final parsed = VersionJson.fromJson(forge);

        final plan = planInstall(version: parsed, host: _linux, paths: _paths);

        final jars = plan.tasks.where(
          (t) =>
              t.targetPath.endsWith('.jar') &&
              t.targetPath.contains('/versions/'),
        );
        expect(
          jars.every((t) => t.targetPath.contains('/1.20.1/')),
          isTrue,
          reason: 'client jar must be the parent version\'s',
        );
        expect(base['id'], '1.20.1');
      },
    );
  });

  group('missingLaunchFiles', () {
    test('reports the client jar and every absent classpath entry', () {
      final version = loadVersion('1.20.1');
      final graph = buildLibraryGraph(version, _linux);
      final missing = missingLaunchFiles(
        version: version,
        classpath: graph.classpathPaths,
        paths: _paths,
        exists: (_) => false,
      );
      expect(missing, hasLength(graph.classpath.length + 1));
      expect(missing.first, '/mc/versions/1.20.1/1.20.1.jar');
    });

    test('reports nothing when everything exists', () {
      final version = loadVersion('1.20.1');
      final graph = buildLibraryGraph(version, _linux);
      expect(
        missingLaunchFiles(
          version: version,
          classpath: graph.classpathPaths,
          paths: _paths,
          exists: (_) => true,
        ),
        isEmpty,
      );
    });
  });

  group('directoryResolver', () {
    test('returns null for a version that is not installed', () {
      final tmp = Directory.systemTemp.createTempSync('resolver_test');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final paths = GamePaths(tmp.path);
      expect(directoryResolver(paths)('1.20.1'), isNull);
    });

    test('reads an installed version from disk', () {
      final tmp = Directory.systemTemp.createTempSync('resolver_test');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final paths = GamePaths(tmp.path);
      Directory('${paths.versions}/1.20.1').createSync(recursive: true);
      File(
        paths.versionJson('1.20.1'),
      ).writeAsStringSync('{"id":"1.20.1","mainClass":"a.B","libraries":[]}');

      final resolved = directoryResolver(paths)('1.20.1');
      expect(resolved, isNotNull);
      expect(resolved!.id, '1.20.1');
      expect(resolved.mainClass, 'a.B');
    });
  });

  group('describeInstall', () {
    test('summarises files, bytes and stages', () {
      final plan = planInstall(
        version: loadVersion('1.20.1'),
        host: _linux,
        paths: _paths,
      );
      final text = describeInstall(plan);
      expect(text, contains('files'));
      expect(text, contains('MB'));
      expect(text, contains('libraries:'));
    });
  });
}
