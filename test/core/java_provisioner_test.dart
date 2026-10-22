import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/mc/host.dart';
import 'package:oh_my_mc/core/mc/java_catalog.dart';
import 'package:oh_my_mc/core/mc/java_lzma.dart';
import 'package:oh_my_mc/core/mc/java_provisioner.dart';
import 'package:oh_my_mc/core/net/cancellation.dart';
import 'package:path/path.dart' as p;

import '../support/java_world.dart';

void main() {
  group('LZMA objects', () {
    test('decodes a real LZMA-alone object whose size field is -1', () async {
      // The 8-byte size in the header is -1 in every Mojang object; the length
      // has to come from the manifest. Without it the decoder returns 0 bytes.
      final compressed = JavaFixtures.javaBytes();
      expect(compressed[5], 0xFF, reason: 'fixture must keep the -1 size');
      final raw = utf8.encode(JavaFixtures.javaRaw);

      final decoded = await decompressJavaObject(
        compressed: compressed,
        rawSize: raw.length,
      );
      expect(decoded, raw);
    });

    test('a wrong declared size is refused rather than written', () async {
      final compressed = JavaFixtures.javaBytes();
      final raw = utf8.encode(JavaFixtures.javaRaw);
      await expectLater(
        decompressJavaObject(compressed: compressed, rawSize: raw.length + 1),
        throwsA(isA<FormatException>()),
      );
    });

    test('a truncated object fails instead of yielding a short file', () async {
      final compressed = JavaFixtures.javaBytes();
      final raw = utf8.encode(JavaFixtures.javaRaw);
      await expectLater(
        decompressJavaObject(
          compressed: compressed.sublist(0, compressed.length - 10),
          rawSize: raw.length,
        ),
        throwsA(anything),
      );
    });

    test('a header that is too short or has no size is refused', () async {
      expect(
        () => decodeJavaObjectSync(compressed: Uint8List(4), rawSize: 100),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => decodeJavaObjectSync(
          compressed: JavaFixtures.javaBytes(),
          rawSize: 0,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('provisioning', () {
    late JavaWorld world;
    late Directory temp;
    late Directory runtimes;

    setUp(() async {
      world = await JavaWorld.start();
      world.publishCatalog(catalogJson());
      world.publishObjects();
      world.publishManifest(
        runtimeManifestJson(baseUrl: 'http://127.0.0.1:PORT'),
      );
      temp = await Directory.systemTemp.createTemp('java_provisioner_test');
      runtimes = Directory(p.join(temp.path, 'runtimes'));
      await runtimes.create(recursive: true);
    });

    tearDown(() async {
      await world.close();
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    /// A manifest whose object URLs point at the live test server.
    JavaRuntimeManifest servedManifest({bool includeExecutable = true}) =>
        JavaRuntimeManifest.fromJson(
          runtimeManifestJson(
            baseUrl: 'http://127.0.0.1:${world.port}',
            includeExecutable: includeExecutable,
          ),
        );

    JavaRuntimeChoice choice() => chooseJavaRuntime(
      catalog: JavaCatalog.fromJson(catalogJson()),
      platform: 'linux',
      requiredMajor: 17,
    );

    test('installs a runtime: raw, compressed, link, executable', () async {
      final provisioner = testProvisioner();
      final result = await provisioner.provision(
        choice: choice(),
        manifest: servedManifest(),
        runtimesDir: runtimes,
        hostOs: HostOs.linux,
      );

      final root = result.root;
      expect(root, p.join(runtimes.path, runtimeDirName(choice())));
      expect(Directory(root).existsSync(), isTrue);

      // Compressed file: decoded back to the original bytes.
      expect(
        File(p.join(root, 'bin/java')).readAsBytesSync(),
        utf8.encode(JavaFixtures.javaRaw),
      );
      // Raw-only file: written as-is, no decompression attempted.
      expect(
        File(p.join(root, 'lib/modules')).readAsBytesSync(),
        utf8.encode(JavaFixtures.modulesRaw),
      );
      // The link resolves to its target's content.
      expect(
        File(p.join(root, 'legal/java.compiler/LICENSE')).readAsBytesSync(),
        utf8.encode(JavaFixtures.licenseRaw),
      );

      expect(result.executable, p.join(root, 'bin/java'));
      expect(File(result.executable).existsSync(), isTrue);
      expect(result.filesWritten, 3);
      expect(result.bytesWritten, greaterThan(0));
      expect(result.skippedEntries, 1);

      // Nothing is left over: no staging tree, no object cache.
      expect(
        Directory('$root.staging').existsSync(),
        isFalse,
        reason: 'the staging directory must be gone after a successful rename',
      );
      expect(Directory(p.join(root, '.objects')).existsSync(), isFalse);

      provisioner.close();
    });

    test('marks the executable +x on POSIX', () async {
      final provisioner = testProvisioner();
      final result = await provisioner.provision(
        choice: choice(),
        manifest: servedManifest(),
        runtimesDir: runtimes,
        hostOs: HostOs.linux,
      );
      final mode = File(result.executable).statSync().mode;
      // owner-execute bit
      expect(mode & 0x40, isNot(0));
      provisioner.close();
    });

    test('a cancel leaves no runtime and no staging directory', () async {
      final cancel = CancelToken();
      final provisioner = testProvisioner();

      // Stall the first object so the cancel lands mid-transfer.
      world.stall = Completer<void>().future;
      final future = provisioner.provision(
        choice: choice(),
        manifest: servedManifest(),
        runtimesDir: runtimes,
        hostOs: HostOs.linux,
        cancel: cancel,
      );

      await Future<void>.delayed(const Duration(milliseconds: 150));
      cancel.cancel();
      world.stall = null;

      await expectLater(future, throwsA(isA<CancelledException>()));

      final name = runtimeDirName(choice());
      expect(
        Directory(p.join(runtimes.path, name)).existsSync(),
        isFalse,
        reason: 'a cancelled install must not look installed',
      );
      expect(
        Directory(p.join(runtimes.path, '$name.staging')).existsSync(),
        isFalse,
        reason: 'a cancelled install must not leave a staging tree',
      );
      provisioner.close();
    });

    test('re-installing replaces the previous runtime', () async {
      final provisioner = testProvisioner();
      final first = await provisioner.provision(
        choice: choice(),
        manifest: servedManifest(),
        runtimesDir: runtimes,
        hostOs: HostOs.linux,
      );
      // Drop a marker: a correct re-install deletes the old tree rather than
      // extracting on top of it.
      File(p.join(first.root, 'stale-marker')).writeAsStringSync('old');

      final second = await provisioner.provision(
        choice: choice(),
        manifest: servedManifest(),
        runtimesDir: runtimes,
        hostOs: HostOs.linux,
      );
      expect(second.root, first.root);
      expect(File(p.join(second.root, 'stale-marker')).existsSync(), isFalse);
      expect(File(second.executable).existsSync(), isTrue);
      provisioner.close();
    });

    test('a missing executable is caught before the rename', () async {
      // A manifest whose "executable" flag is on nothing: the runtime would be
      // installed and then fail at launch, so it must fail here instead.
      final manifest = JavaRuntimeManifest.fromJson(
        runtimeManifestJson(
          baseUrl: 'http://127.0.0.1:${world.port}',
          includeExecutable: false,
          javaPath: 'bin/not-java',
        ),
      );
      final provisioner = testProvisioner();
      await expectLater(
        provisioner.provision(
          choice: choice(),
          manifest: manifest,
          runtimesDir: runtimes,
          hostOs: HostOs.linux,
        ),
        throwsA(isA<StateError>()),
      );
      final name = runtimeDirName(choice());
      expect(Directory(p.join(runtimes.path, name)).existsSync(), isFalse);
      expect(
        Directory(p.join(runtimes.path, '$name.staging')).existsSync(),
        isFalse,
      );
      provisioner.close();
    });

    test('a manifest that declares no files is refused', () async {
      final manifest = JavaRuntimeManifest.fromJson({
        'files': {
          'bin': {'type': 'directory'},
        },
      });
      final provisioner = testProvisioner();
      await expectLater(
        provisioner.provision(
          choice: choice(),
          manifest: manifest,
          runtimesDir: runtimes,
          hostOs: HostOs.linux,
        ),
        throwsA(isA<StateError>()),
      );
      provisioner.close();
    });

    test('a link escaping the runtime is refused', () async {
      final manifest = JavaRuntimeManifest.fromJson(
        runtimeManifestJson(
          baseUrl: 'http://127.0.0.1:${world.port}',
          linkPath: 'legal/java.compiler/LICENSE',
          linkTarget: '../../../../etc/passwd',
        ),
      );
      final provisioner = testProvisioner();
      await expectLater(
        provisioner.provision(
          choice: choice(),
          manifest: manifest,
          runtimesDir: runtimes,
          hostOs: HostOs.linux,
        ),
        throwsA(anyOf(isA<FormatException>(), isA<StateError>())),
      );
      provisioner.close();
    });

    test('an entry path that traverses out is refused', () async {
      final manifest = JavaRuntimeManifest.fromJson(
        runtimeManifestJson(
          baseUrl: 'http://127.0.0.1:${world.port}',
          modulesPath: '../../escape/modules',
        ),
      );
      final provisioner = testProvisioner();
      await expectLater(
        provisioner.provision(
          choice: choice(),
          manifest: manifest,
          runtimesDir: runtimes,
          hostOs: HostOs.linux,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        Directory(p.join(temp.path, 'escape')).existsSync(),
        isFalse,
        reason: 'nothing may be written outside the runtimes directory',
      );
      provisioner.close();
    });

    test('a server that 404s every object fails without a runtime', () async {
      world.failEverything = true;
      final provisioner = testProvisioner();
      await expectLater(
        provisioner.provision(
          choice: choice(),
          manifest: servedManifest(),
          runtimesDir: runtimes,
          hostOs: HostOs.linux,
        ),
        throwsA(anything),
      );
      final name = runtimeDirName(choice());
      expect(Directory(p.join(runtimes.path, name)).existsSync(), isFalse);
      provisioner.close();
    });

    test('progress reports every phase in order', () async {
      final provisioner = testProvisioner();
      final phases = <JavaProvisionPhase>[];
      await provisioner.provision(
        choice: choice(),
        manifest: servedManifest(),
        runtimesDir: runtimes,
        hostOs: HostOs.linux,
        onProgress: (progress) {
          if (phases.isEmpty || phases.last != progress.phase) {
            phases.add(progress.phase);
          }
        },
      );
      expect(
        phases,
        containsAllInOrder([
          JavaProvisionPhase.manifest,
          JavaProvisionPhase.download,
          JavaProvisionPhase.extract,
          JavaProvisionPhase.links,
          JavaProvisionPhase.verify,
        ]),
      );
      provisioner.close();
    });

    test(
      'macOS layout is taken from the manifest, not from <root>/bin/java',
      () async {
        final manifest = JavaRuntimeManifest.fromJson(
          runtimeManifestJson(
            baseUrl: 'http://127.0.0.1:${world.port}',
            javaPath: 'jre.bundle/Contents/Home/bin/java',
            modulesPath: 'jre.bundle/Contents/Home/lib/modules',
            linkPath: 'jre.bundle/Contents/Home/legal/java.compiler/LICENSE',
            licensePath: 'jre.bundle/Contents/Home/legal/java.base/LICENSE',
          ),
        );
        final provisioner = testProvisioner();
        final result = await provisioner.provision(
          choice: choice(),
          manifest: manifest,
          runtimesDir: runtimes,
          hostOs: HostOs.osx,
        );
        expect(
          result.executable,
          endsWith(p.join('jre.bundle', 'Contents', 'Home', 'bin', 'java')),
        );
        expect(File(result.executable).existsSync(), isTrue);
        provisioner.close();
      },
    );
  });

  group('runtime directory naming', () {
    test('includes component and version so two builds never collide', () {
      final catalog = JavaCatalog.fromJson(catalogJson());
      final first = chooseJavaRuntime(
        catalog: catalog,
        platform: 'linux',
        requiredMajor: 17,
      );
      final second = chooseJavaRuntime(
        catalog: catalog,
        platform: 'linux',
        requiredMajor: 21,
      );
      expect(runtimeDirName(first), 'java-runtime-gamma-17.0.15');
      expect(runtimeDirName(second), 'java-runtime-delta-21.0.7');
      expect(runtimeDirName(first), isNot(runtimeDirName(second)));
    });
  });
}
