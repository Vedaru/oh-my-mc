import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/mc/host.dart';
import 'package:oh_my_mc/core/mc/java_catalog.dart';
import 'package:path/path.dart' as p;

import '../support/java_world.dart';

void main() {
  group('platform keys', () {
    test('macOS uses "mac-os", not the mcName "osx"', () {
      // Building the key from HostOs.mcName would produce "osx", which the
      // catalog does not contain - and every macOS install would fail with
      // "no runtimes published for osx".
      expect(javaPlatformKey(HostOs.osx, HostArch.x86_64), 'mac-os');
      expect(javaPlatformKey(HostOs.osx, HostArch.arm64), 'mac-os-arm64');
      expect(HostOs.osx.mcName, 'osx');
    });

    test('linux splits 32-bit, windows splits all three', () {
      expect(javaPlatformKey(HostOs.linux, HostArch.x86), 'linux-i386');
      expect(javaPlatformKey(HostOs.linux, HostArch.x86_64), 'linux');
      expect(javaPlatformKey(HostOs.linux, HostArch.arm64), 'linux');
      expect(javaPlatformKey(HostOs.windows, HostArch.x86), 'windows-x86');
      expect(javaPlatformKey(HostOs.windows, HostArch.x86_64), 'windows-x64');
      expect(javaPlatformKey(HostOs.windows, HostArch.arm64), 'windows-arm64');
    });

    test('every real platform in the shipped fixture is addressable', () {
      final real = JavaCatalog.fromJson(
        jsonDecode(File('test/fixtures/java/all.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      final reachable = <String>{
        for (final os in HostOs.values)
          for (final arch in HostArch.values) javaPlatformKey(os, arch),
      };
      for (final key in real.platformKeys) {
        expect(
          reachable,
          contains(key),
          reason: '$key is in the catalog but no (os, arch) maps to it',
        );
      }
    });
  });

  group('catalog parsing', () {
    late JavaCatalog catalog;

    setUp(() {
      catalog = JavaCatalog.fromJson(catalogJson());
    });

    test('lists components per platform', () {
      expect(
        catalog.componentsFor('linux').keys,
        containsAll([
          'jre-legacy',
          'java-runtime-alpha',
          'java-runtime-gamma',
          'java-runtime-delta',
          'java-runtime-epsilon',
        ]),
      );
    });

    test('a component published as an empty array is not available', () {
      // This is the real arm64 shape: the key exists, the list is empty.
      // The key exists with an empty list - the caller must look at the builds,
      // and that is exactly what `chooseJavaRuntime` does.
      expect(catalog.builds('mac-os-arm64', 'jre-legacy'), isEmpty);
      expect(
        catalog.builds('mac-os-arm64', 'java-runtime-gamma'),
        hasLength(1),
      );
    });

    test('parses the build version and manifest URL', () {
      final build = catalog.builds('linux', 'java-runtime-gamma').single;
      expect(build.versionName, '17.0.15');
      expect(build.manifestUrl, contains('17.0.15'));
    });

    test('a document with no platforms is refused', () {
      expect(
        () => JavaCatalog.fromJson(const {}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('runtime manifest parsing', () {
    late JavaRuntimeManifest manifest;

    setUp(() {
      manifest = JavaRuntimeManifest.fromJson(
        runtimeManifestJson(baseUrl: 'http://x'),
      );
    });

    test('classifies file, directory and link entries', () {
      final byPath = {for (final e in manifest.entries) e.path: e};
      expect(byPath['bin']!.kind, JavaEntryKind.directory);
      expect(byPath['bin/java']!.kind, JavaEntryKind.file);
      expect(byPath['legal/java.compiler/LICENSE']!.kind, JavaEntryKind.link);
      expect(
        byPath['legal/java.compiler/LICENSE']!.target,
        '../java.base/LICENSE',
      );
      // The link's target is itself a plain file in the same manifest.
      expect(byPath['legal/java.base/LICENSE']!.kind, JavaEntryKind.file);
    });

    test('an unknown entry kind is skipped, not fatal', () {
      expect(manifest.skipped, 1);
      expect(manifest.entries.any((e) => e.path == 'weird-entry'), isFalse);
    });

    test('prefers the lzma object and counts wire vs disk bytes', () {
      final java = manifest.entries.firstWhere((e) => e.path == 'bin/java');
      expect(java.isCompressed, isTrue);
      expect(java.preferredDownload!.url, endsWith('java.lzma'));
      // The compressed object is smaller than what it expands to.
      expect(java.wireBytes, lessThan(java.diskBytes));

      final modules = manifest.files.firstWhere((e) => e.path == 'lib/modules');
      expect(modules.isCompressed, isFalse);
      expect(modules.preferredDownload!.url, endsWith('modules.raw'));
      expect(modules.wireBytes, modules.diskBytes);
    });

    test('wire total is smaller than the disk total', () {
      expect(manifest.wireBytes, lessThan(manifest.diskBytes));
      expect(manifest.wireBytes, greaterThan(0));
    });

    test('the executable is found from the manifest, not assumed', () {
      expect(manifest.javaExecutable(os: HostOs.linux), 'bin/java');
      expect(manifest.javaExecutable(os: HostOs.windows), 'bin/java');

      // macOS roots its tree inside the bundle; the manifest is what says so.
      final mac = JavaRuntimeManifest.fromJson(
        runtimeManifestJson(
          baseUrl: 'http://x',
          javaPath: 'jre.bundle/Contents/Home/bin/java',
          modulesPath: 'jre.bundle/Contents/Home/lib/modules',
          linkPath: 'jre.bundle/Contents/Home/legal/java.base/LICENSE',
        ),
      );
      expect(
        mac.javaExecutable(os: HostOs.osx),
        'jre.bundle/Contents/Home/bin/java',
      );
    });

    test('a manifest with no usable files is refused', () {
      expect(
        () => JavaRuntimeManifest.fromJson({
          'files': {
            'x': {'type': 'nonsense'},
          },
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => JavaRuntimeManifest.fromJson(const {}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('component selection', () {
    late JavaCatalog catalog;

    setUp(() {
      catalog = JavaCatalog.fromJson(catalogJson());
    });

    test('honours the declared component when the platform has it', () {
      final choice = chooseJavaRuntime(
        catalog: catalog,
        platform: 'linux',
        requiredMajor: 17,
        declaredComponent: 'java-runtime-gamma',
      );
      expect(choice.component, 'java-runtime-gamma');
      expect(choice.majorVersion, 17);
    });

    test(
      'falls back to a same-major component when the declared one is absent',
      () {
        // mac-os-arm64 publishes no jre-legacy; gamma is what it has for 17.
        final choice = chooseJavaRuntime(
          catalog: catalog,
          platform: 'mac-os-arm64',
          requiredMajor: 17,
          declaredComponent: 'java-runtime-gamma-snapshot',
        );
        expect(choice.component, 'java-runtime-gamma');
      },
    );

    test('picks the exact major, never a newer one, when both exist', () {
      final choice = chooseJavaRuntime(
        catalog: catalog,
        platform: 'linux',
        requiredMajor: 17,
      );
      expect(choice.majorVersion, 17);
      expect(choice.component, 'java-runtime-gamma');
    });

    test('a newer major is accepted when the exact one is missing', () {
      final choice = chooseJavaRuntime(
        catalog: catalog,
        platform: 'linux',
        requiredMajor: 22,
      );
      expect(choice.component, 'java-runtime-epsilon');
      expect(choice.majorVersion, 25);
    });

    test('an older-only catalog is a refusal, not a wrong-arch download', () {
      // Java 8 on Apple Silicon: the catalog lists jre-legacy but publishes
      // nothing for it. Shipping the x86_64 JRE would install fine and then
      // fail to start, which is the worst possible outcome.
      expect(
        () => chooseJavaRuntime(
          catalog: catalog,
          platform: 'mac-os-arm64',
          requiredMajor: 8,
        ),
        throwsA(
          isA<JavaUnavailableException>()
              .having((e) => e.platform, 'platform', 'mac-os-arm64')
              .having((e) => e.requiredMajor, 'requiredMajor', 8),
        ),
      );
    });

    test('an unknown platform is a refusal', () {
      expect(
        () => chooseJavaRuntime(
          catalog: catalog,
          platform: 'plan9',
          requiredMajor: 17,
        ),
        throwsA(isA<JavaUnavailableException>()),
      );
    });

    test('unknown components in the catalog cannot win selection', () {
      // `minecraft-java-exe` is real and is not a JRE.
      final choice = chooseJavaRuntime(
        catalog: catalog,
        platform: 'linux',
        requiredMajor: 17,
      );
      expect(choice.component, isNot('minecraft-java-exe'));
    });
  });

  group('shipped catalog fixture', () {
    test('parses the trimmed real document and keeps the arm64 gaps', () {
      final real = JavaCatalog.fromJson(
        jsonDecode(File('test/fixtures/java/all.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      expect(real.platformKeys, contains('mac-os-arm64'));
      expect(real.builds('mac-os-arm64', 'jre-legacy'), isEmpty);
      expect(real.builds('linux', 'jre-legacy'), isNotEmpty);
      // The real manifest for 17.0.15 is served from piston-meta, which the
      // existing mirror chain already knows how to classify.
      expect(
        real.builds('linux', 'java-runtime-gamma').single.manifestUrl,
        contains('piston-meta.mojang.com'),
      );
    });
  });

  group('HTTP', () {
    late JavaWorld world;
    late Directory temp;

    setUp(() async {
      world = await JavaWorld.start();
      temp = await Directory.systemTemp.createTemp('java_catalog_test');
    });

    tearDown(() async {
      await world.close();
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('fetches and parses a catalog over HTTP', () async {
      world.publishCatalog(catalogJson());
      final provisioner = testProvisioner();
      final catalog = await provisioner.fetchCatalog(world.url('/all.json'));
      expect(catalog.platformKeys, contains('linux'));
      provisioner.close();
    });

    test('an HTML error page is not parsed as a catalog', () async {
      world.files['/all.json'] = utf8.encode('<html>captive portal</html>');
      final provisioner = testProvisioner();
      await expectLater(
        provisioner.fetchCatalog(world.url('/all.json')),
        throwsA(isA<FormatException>()),
      );
      provisioner.close();
    });

    test('a 404 is an HttpException naming the URL', () async {
      final provisioner = testProvisioner();
      await expectLater(
        provisioner.fetchCatalog(world.url('/missing.json')),
        throwsA(
          isA<HttpException>().having(
            (e) => e.message,
            'message',
            contains('404'),
          ),
        ),
      );
      provisioner.close();
    });

    test('the fixture fixture path is absolute so it works from test/', () {
      expect(p.isAbsolute(p.absolute('test/fixtures/java/all.json')), isTrue);
    });
  });
}
