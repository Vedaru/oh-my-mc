@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/core/mc/asset_index.dart';
import 'package:oh_my_mc/core/mc/host.dart';
import 'package:oh_my_mc/core/install/version_installer.dart';
import 'package:oh_my_mc/core/mc/forge_install.dart';
import 'package:oh_my_mc/core/mc/java_catalog.dart';
import 'package:oh_my_mc/core/mc/java_manager.dart';
import 'package:oh_my_mc/core/mc/java_provisioner.dart';
import 'package:oh_my_mc/core/mc/install_plan.dart';
import 'package:oh_my_mc/core/mc/launch_service.dart';
import 'package:oh_my_mc/core/mc/loader_meta.dart';
import 'package:oh_my_mc/core/mc/local_host.dart';
import 'package:oh_my_mc/core/mc/version_json.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:path/path.dart' as p;

/// The installation paths, run against the real services.
///
/// This is the only test that talks to Mojang, Fabric, Quilt, Forge, NeoForge and
/// the Java runtime catalog, downloads hundreds of megabytes and runs a real
/// installer jar, so it is tagged `e2e` and excluded from CI:
///
///   flutter test test/e2e/install_paths_e2e_test.dart --tags e2e
///
/// It exists because every one of these paths has a failure mode that unit tests
/// with local servers cannot see: a moved URL, a redirect to a CDN, a legacy asset
/// layout, an installer that exits 0 while doing nothing.
void main() {
  // One tree for the whole run: the paths share libraries and assets on purpose,
  // which is exactly what the launcher does.
  late Directory data;
  late GamePaths paths;
  String? provisionedJava;
  final host = localRuleContext();

  setUpAll(() async {
    // `E2E_TREE=/path` reuses a previous run's tree (the installs are the slow
    // part); otherwise a fresh temp directory per run.
    final reuse = Platform.environment['E2E_TREE'];
    data = reuse != null && reuse.isNotEmpty
        ? Directory(reuse)
        : await Directory.systemTemp.createTemp('omc-e2e');
    paths = GamePaths(p.join(data.path, 'minecraft'));
  });

  tearDownAll(() async {
    // Keep the tree when the run failed: the point of a failure is to look at it.
    final reused = (Platform.environment['E2E_TREE'] ?? '').isNotEmpty;
    if (data.existsSync() &&
        !reused &&
        !Platform.environment.containsKey('E2E_KEEP')) {
      await data.delete(recursive: true);
    } else {
      // ignore: avoid_print
      print('e2e tree kept at ${data.path}');
    }
  });

  VersionInstaller installer() => VersionInstaller();

  Future<VersionJson> versionJson(String id) async => VersionJson.fromJson(
    jsonDecode(await File(paths.versionJson(id)).readAsString())
        as Map<String, dynamic>,
  );

  JavaRuntime fakeJava(int major) => JavaRuntime(
    path: '/e2e/java/bin/java',
    majorVersion: major,
    versionString: '$major.0.0',
    vendor: 'e2e',
    arch: HostArch.x86_64,
  );

  /// A runtime standing in for a scanned JVM. `prepareLaunch` only reads the major
  /// version and the path's existence, so this keeps the resource paths
  /// independent of whatever Java this machine has.
  /// The production path: `prepareInstanceLaunch` resolves the `inheritsFrom`
  /// chain, so a loader version is launched as its merged self rather than as the
  /// delta the loader wrote. Calling the lower-level `prepareLaunch` with the raw
  /// JSON is what made the first version of this file report false failures.
  Future<LaunchOutcome> launchOf(
    String versionId, {
    required int javaMajor,
    IsolationKind isolation = IsolationKind.shareLibraries,
  }) {
    final launcherPaths = LauncherPaths(
      data: data,
      game: Directory(paths.root),
    );
    return prepareInstanceLaunch(
      instance: Instance(
        id: 'e2e',
        name: 'e2e',
        versionId: versionId,
        isolation: isolation,
        createdAt: DateTime(2026),
      ),
      paths: launcherPaths,
      settings: AppSettings.defaults,
      javaManager: JavaManager(
        hostOs: localHostOs,
        known: [fakeJava(javaMajor)],
      ),
    );
  }

  group('vanilla', () {
    test('1.20.1 installs every stage and prepares a launch', () async {
      final result = await installer().install(
        versionId: '1.20.1',
        paths: paths,
        host: host,
      );

      // The tree the launch pipeline needs, one file at a time.
      expect(File(paths.versionJson('1.20.1')).existsSync(), isTrue);
      expect(File(paths.versionJar('1.20.1')).existsSync(), isTrue);
      expect(
        File(paths.versionJar('1.20.1')).lengthSync(),
        greaterThan(1 << 20),
      );
      expect(Directory(paths.libraries).listSync().isNotEmpty, isTrue);

      final version = await versionJson('1.20.1');
      final indexPath = File(paths.assetIndexFile(version.assetIndex!.id));
      expect(indexPath.existsSync(), isTrue, reason: 'asset index');

      // Objects are content-addressed: one indexed object on disk is enough to
      // prove the hashed layout was used, and the count proves it was not one.
      final objects = Directory(paths.assetObjects)
          .listSync(recursive: true)
          .whereType<File>()
          .toList();
      expect(objects.length, greaterThan(100));
      expect(result.verification.problems, isEmpty);
      expect(result.verification.checkedFiles, greaterThan(100));

      // The install is only useful if a command line comes out of it.
      final outcome = await launchOf('1.20.1', javaMajor: 17);
      expect(
        outcome,
        isA<LaunchReady>(),
        reason: outcome is LaunchRefused
            ? outcome.blockers.map((b) => b.message).join('; ')
            : null,
      );
      final argv = (outcome as LaunchReady).plan.args;
      expect(argv, contains('net.minecraft.client.main.Main'));
      expect(argv, contains('--gameDir'));
    }, timeout: const Timeout(Duration(minutes: 20)));

    test('1.6.4 materialises the virtual asset layout', () async {
      // 1.7.10's index is a plain hashed one; the `virtual: true` layout belongs
      // to the `legacy` index that 1.6.x points at, and that is the layout a
      // launcher actually has to materialise.
      await installer().install(versionId: '1.6.4', paths: paths, host: host);

      final version = await versionJson('1.6.4');
      // The layout is a property of the index file itself (`virtual` /
      // `map_to_resources`), so read it the way the installer does.
      final indexFile = File(paths.assetIndexFile(version.assetIndex!.id));
      final index = AssetIndex.fromJson(
        jsonDecode(await indexFile.readAsString()) as Map<String, dynamic>,
      );
      final layout = index.layout;

      // `virtual: true`: files must also appear under assets/virtual/<id> for the
      // game to open them by resource name.
      expect(layout, isNot(AssetLayout.hashed));
      final virtual = Directory(
        '${paths.virtualAssets}/${version.assetIndex!.id}',
      );
      expect(
        virtual.existsSync() && virtual.listSync().isNotEmpty,
        isTrue,
        reason: 'legacy virtual assets at ${virtual.path}',
      );

      // And it still builds a command line (Java 8 is what it declares).
      final outcome = await launchOf('1.6.4', javaMajor: 8);
      expect(
        outcome,
        isA<LaunchReady>(),
        reason: outcome is LaunchRefused
            ? outcome.blockers.map((b) => b.message).join('; ')
            : null,
      );
    }, timeout: const Timeout(Duration(minutes: 20)));
  });

  group('loader profiles', () {
    for (final kind in [LoaderKind.fabric, LoaderKind.quilt]) {
      test('${kind.name} installs a profile that inherits 1.20.1', () async {
        final meta = LoaderMeta();
        addTearDown(meta.close);

        final available = await meta.loaderVersions(kind, '1.20.1');
        expect(available, isNotEmpty, reason: '${kind.name} build list');

        final id = await LoaderProfileWriter(meta).prepare(
          kind: kind,
          gameVersion: '1.20.1',
          loaderVersion: available.first,
          paths: paths,
        );
        expect(id, LoaderMeta.profileId(kind, '1.20.1', available.first));

        final result = await installer().install(
          versionId: id,
          paths: paths,
          host: host,
          includeAssets: false,
        );
        expect(result.verification.problems, isEmpty);

        final version = await versionJson(id);
        expect(version.inheritsFrom, '1.20.1');
        expect(version.mainClass, isNotEmpty);

        // The loader's own libraries came from its maven, and the parent's from
        // the vanilla install: one classpath, no missing entries. This goes
        // through the production entry point, which is what merges the chain.
        final outcome = await launchOf(id, javaMajor: 17);
        expect(
          outcome,
          isA<LaunchReady>(),
          reason: outcome is LaunchRefused
              ? outcome.blockers.map((b) => b.message).join('; ')
              : null,
        );
      }, timeout: const Timeout(Duration(minutes: 20)));
    }
  });

  group('java', () {
    test('the catalog resolves and a runtime installs', () async {
      final provisioner = JavaProvisioner();
      addTearDown(provisioner.close);

      final catalog = await provisioner.fetchCatalog(Uri.parse(javaCatalogUri));
      final choice = chooseJavaRuntime(
        catalog: catalog,
        platform: javaPlatformKey(localHostOs, localHostArch),
        requiredMajor: 21,
      );
      expect(choice, isNotNull, reason: 'a Java 21 build for this host');

      final manifest = await provisioner.fetchManifest(choice.build);
      final result = await provisioner.provision(
        choice: choice,
        manifest: manifest,
        runtimesDir: Directory(p.join(data.path, 'runtimes')),
        hostOs: localHostOs,
      );

      final java = File(result.executable);
      expect(java.existsSync(), isTrue);
      final probe = await Process.run(java.path, ['-version']);
      final banner = '${probe.stdout}${probe.stderr}';
      expect(banner, contains('version'));

      // ...and the launcher's own scan finds it without being told where it is.
      final manager = JavaManager(hostOs: localHostOs);
      final found = await manager.scan(
        environment: const {},
        managedRoots: managedJavaExecutables(data),
      );
      expect(
        found.map((r) => r.path),
        contains(java.path),
        reason: 'managed runtimes are scanned',
      );
      provisionedJava = java.path;
    }, timeout: const Timeout(Duration(minutes: 30)));
  });

  group('installer-jar loaders', () {
    Future<void> installs(LoaderKind kind, String gameVersion) async {
      // Both installers demand the vanilla client jar in the same tree.
      if (!File(paths.versionJar(gameVersion)).existsSync()) {
        await installer().install(
          versionId: gameVersion,
          paths: paths,
          host: host,
          includeAssets: false,
        );
      }
      final forge = ForgeMeta();
      addTearDown(forge.close);
      final loaderVersion = await forge.recommendedVersion(kind, gameVersion);
      final runner = ForgeInstaller(meta: forge);
      addTearDown(runner.close);

      final id = await runner.install(
        kind: kind,
        gameVersion: gameVersion,
        loaderVersion: loaderVersion,
        paths: paths,
        java: provisionedJava!,
      );

      expect(id, ForgeMeta.versionId(kind, gameVersion, loaderVersion));
      expect(File(paths.versionJson(id)).existsSync(), isTrue);
      expect(
        File('${paths.root}/launcher_profiles.json').existsSync(),
        isTrue,
        reason: 'the installer refuses a directory without it',
      );

      final version = await versionJson(id);
      expect(version.inheritsFrom, gameVersion);
      final outcome = await launchOf(id, javaMajor: 21);
      expect(
        outcome,
        isA<LaunchReady>(),
        reason: outcome is LaunchRefused
            ? outcome.blockers.map((b) => b.message).join('; ')
            : null,
      );
    }

    test('forge installs 1.20.1', () async {
      expect(provisionedJava, isNotNull, reason: 'run the java test first');
      await installs(LoaderKind.forge, '1.20.1');
    }, timeout: const Timeout(Duration(minutes: 30)));

    test('neoforge installs 1.21.1', () async {
      expect(provisionedJava, isNotNull, reason: 'run the java test first');
      await installs(LoaderKind.neoforge, '1.21.1');
    }, timeout: const Timeout(Duration(minutes: 30)));
  });

  group('isolation', () {
    test('an isolated instance launches from shared resources', () async {
      final launcherPaths = LauncherPaths(
        data: data,
        game: Directory(paths.root),
      );
      final instance = Instance(
        id: 'iso',
        name: 'Iso',
        versionId: '1.20.1',
        isolation: IsolationKind.isolated,
        createdAt: DateTime(2026),
      );
      // The instance's own game directory does not exist yet, and must not have to:
      // the installer writes to the shared tree, the game creates its own folder.
      final gameDir = launcherPaths.gamePathsFor(instance).root;
      expect(Directory(gameDir).existsSync(), isFalse);

      final manager = JavaManager(hostOs: localHostOs, known: const []);
      await manager.scan(
        environment: const {},
        managedRoots: managedJavaExecutables(data),
      );

      final outcome = await prepareInstanceLaunch(
        instance: instance,
        paths: launcherPaths,
        settings: AppSettings.defaults,
        javaManager: manager,
      );
      expect(
        outcome,
        isA<LaunchReady>(),
        reason: outcome is LaunchRefused
            ? outcome.blockers.map((b) => b.message).join('; ')
            : null,
      );

      final argv = (outcome as LaunchReady).plan.args;
      final gameDirFlag = argv.indexOf('--gameDir');
      expect(gameDirFlag, greaterThanOrEqualTo(0));
      // The version, libraries and assets stay shared; only the game directory
      // moves into the instance.
      expect(argv[gameDirFlag + 1], p.normalize(p.absolute(gameDir)));
      expect(
        (outcome.plan.args.join(' ')),
        contains(paths.libraries),
        reason: 'libraries come from the shared tree',
      );
    }, timeout: const Timeout(Duration(minutes: 10)));
  });

  test('nothing in the shared tree is a zero-byte file', () async {
    // Cheap final sweep: an interrupted download leaves empty files behind, and
    // they are invisible to "the file exists" checks everywhere else.
    final empty = <String>[];
    for (final entity in Directory(paths.root).listSync(recursive: true)) {
      if (entity is File && entity.lengthSync() == 0) empty.add(entity.path);
    }
    expect(empty, isEmpty, reason: 'zero-byte files: $empty');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
