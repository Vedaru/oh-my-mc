import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/mc/version_resolver.dart';
import 'package:oh_my_mc/core/mc/host.dart';
import 'package:oh_my_mc/core/mc/library_graph.dart';
import 'package:oh_my_mc/core/mc/rules.dart';
import 'package:oh_my_mc/core/mc/version_json.dart';

import 'fixtures.dart';

const _linux = RuleContext(os: HostOs.linux, arch: HostArch.x86_64);
const _win = RuleContext(os: HostOs.windows, arch: HostArch.x86_64);
const _macArm = RuleContext(os: HostOs.osx, arch: HostArch.arm64);

void expectParsedLibraries(VersionJson v, int expectedCount) {
  expect(
    v.libraries,
    hasLength(expectedCount),
    reason: 'library count for ${v.id}',
  );
  for (final lib in v.libraries) {
    expect(lib.name, isNotEmpty);
    expect(lib.group, isNotEmpty);
    expect(lib.artifact, isNotEmpty);
    expect(lib.version, isNotEmpty, reason: '${lib.name} in ${v.id}');
  }
}

void main() {
  group('version parsing over real fixtures', () {
    for (final id in capturedVersions) {
      test('$id parses with complete coordinates', () {
        final v = loadVersion(id);
        expect(v.raw, isNotEmpty, reason: 'raw escape hatch preserved');
        expect(v.id, id);
        expect(v.mainClass, isNotEmpty);
        expect(v.libraries, isNotEmpty);
        expectParsedLibraries(v, v.libraries.length);
      });
    }

    test('modern versions expose arguments.game and default-user-jvm', () {
      final modern = loadVersion('26.3');
      expect(modern.usesModernArguments, isTrue);
      expect(modern.minecraftArguments, isNull);
      expect(modern.arguments.game, isNotEmpty);
      // Newer than the plan assumed: 26.3 ships a suggested memory/GC block.
      expect(
        modern.arguments.defaultUserJvm,
        isNotEmpty,
        reason: '26.3 carries default-user-jvm',
      );

      final oneTwenty = loadVersion('1.20.1');
      expect(oneTwenty.arguments.defaultUserJvm, isEmpty);
    });

    test(
      'legacy versions expose minecraftArguments and no arguments block',
      () {
        for (final id in ['1.12.2', '1.8.9', '1.6.4', '1.5.2']) {
          final v = loadVersion(id);
          expect(v.usesModernArguments, isFalse, reason: id);
          expect(v.minecraftArguments, isNotNull, reason: id);
          expect(v.minecraftArguments, contains(r'${auth_player_name}'));
        }
      },
    );

    test('java major versions match the documented progression', () {
      expect(loadVersion('26.3').javaVersion!.majorVersion, 25);
      expect(loadVersion('1.20.1').javaVersion!.majorVersion, 17);
      expect(loadVersion('1.12.2').javaVersion!.majorVersion, 8);
    });

    test('unknown fields survive the raw round trip', () {
      final v = loadVersion('1.20.1');
      expect(v.toJson()['logging'], isNotNull);
      expect(v.toJson()['minimumLauncherVersion'], isNotNull);
    });
  });

  group('library graph', () {
    test('every modern library resolves a classpath path on linux', () {
      final v = loadVersion('26.3');
      final graph = buildLibraryGraph(v, _linux);
      expect(graph.classpath, isNotEmpty);
      for (final f in graph.classpath) {
        expect(f.path, endsWith('.jar'));
        expect(f.sha1, isNotEmpty);
        expect(f.url, startsWith('https://'));
      }
    });

    test('classpath order is metadata order', () {
      final v = loadVersion('1.20.1');
      final graph = buildLibraryGraph(v, _linux);
      final expected = <String>[
        for (final lib in v.libraries)
          if (ruleAllows(lib.rules, _linux))
            if (lib.downloads?.artifact != null) lib.downloads!.artifact!.path,
      ];
      expect(
        graph.classpath.map((f) => f.path).toList(),
        expected,
        reason: 'filtering must not reorder',
      );
      expect(graph.classpath, isNotEmpty);
      expect(
        graph.classpath.map((f) => f.path).toSet(),
        hasLength(graph.classpath.length),
        reason: 'no duplicate paths',
      );
    });

    test('javadoc is not mistaken for a classpath entry', () {
      final graph = buildLibraryGraph(loadVersion('1.20.1'), _linux);
      expect(graph.classpath.where((f) => f.path.contains('javadoc')), isEmpty);
    });

    test('mac-only libraries are genuinely excluded on linux', () {
      final v = loadVersion('26.3');
      final linux = buildLibraryGraph(v, _linux);
      expect(
        linux.classpath.where((f) => f.path.contains('java-objc-bridge')),
        isEmpty,
      );

      final mac = buildLibraryGraph(v, _macArm);
      expect(
        mac.classpath.where((f) => f.path.contains('java-objc-bridge')),
        isNotEmpty,
      );
    });

    test('excluded libraries are recorded, not silently dropped', () {
      final graph = buildLibraryGraph(loadVersion('26.3'), _linux);
      expect(graph.skipped, isNotEmpty);
    });

    group('legacy natives', () {
      test('1.12.2 yields per-platform native archives', () {
        final v = loadVersion('1.12.2');

        final linux = buildLibraryGraph(v, _linux);
        expect(linux.natives, isNotEmpty);
        for (final n in linux.natives) {
          expect(n.file.path, contains('natives-linux'));
          expect(n.exclude, contains('META-INF/'));
        }

        final win = buildLibraryGraph(v, _win);
        for (final n in win.natives) {
          expect(n.file.path, contains('natives-windows'));
        }
      });

      test('complementary lwjgl-platform entries do not duplicate natives', () {
        // 1.12.2 declares 2.9.4 (allow, disallow osx) and 2.9.2 (allow osx).
        final mac = buildLibraryGraph(loadVersion('1.12.2'), _macArm);
        final lwjgl = mac.natives
            .where((n) => n.file.path.contains('lwjgl-platform'))
            .toList();
        expect(lwjgl, hasLength(1));
        expect(lwjgl.single.file.path, contains('2.9.2'));

        final linux = buildLibraryGraph(loadVersion('1.12.2'), _linux);
        final lwjglLinux = linux.natives
            .where((n) => n.file.path.contains('lwjgl-platform'))
            .toList();
        expect(lwjglLinux, hasLength(1));
        expect(lwjglLinux.single.file.path, contains('2.9.4'));
      });

      test('modern versions have no legacy natives mapping', () {
        final graph = buildLibraryGraph(loadVersion('26.3'), _linux);
        expect(graph.natives, isEmpty);
      });

      test('natives are also part of the download set', () {
        final graph = buildLibraryGraph(loadVersion('1.12.2'), _linux);
        final jarPaths = graph.jars.map((f) => f.path).toSet();
        for (final n in graph.natives) {
          expect(jarPaths, contains(n.file.path));
        }
        expect(
          graph.jars.length,
          graph.classpath.length + graph.natives.length,
        );
      });

      test('arch-classified natives are not collapsed together', () {
        // Regression: netty ships linux-x86_64 and linux-aarch_64 variants that
        // both carry only `allow linux`, so a group:artifact dedupe key would
        // keep just the last one and could drop the arch the host needs. Both
        // belong on the classpath — netty selects at runtime.
        final v = loadVersion('1.20.1');
        const linuxArm = RuleContext(os: HostOs.linux, arch: HostArch.arm64);

        final onArm = buildLibraryGraph(v, linuxArm).classpath
            .map((f) => f.path)
            .where((p) => p.contains('netty-transport-native-epoll'))
            .toList();

        expect(onArm, hasLength(2));
        expect(onArm, contains(contains('linux-aarch_64')));
        expect(onArm, contains(contains('linux-x86_64')));
      });
    });
  });

  group('inheritance', () {
    VersionJson parse(Map<String, Object?> json) =>
        VersionJson.fromJson(json.cast<String, dynamic>());

    test('the client jar comes from the base version, not the loader id', () {
      final parent = parse({
        'id': '1.20.1',
        'type': 'release',
        'mainClass': 'net.minecraft.client.main.Main',
        'assets': '5',
        'assetIndex': {'id': '5', 'sha1': '', 'size': 0, 'url': ''},
        'libraries': [
          {'name': 'com.example:parent:1.0'},
        ],
        'downloads': {
          'client': {'sha1': '', 'size': 0, 'url': ''},
        },
      });
      final child = parse({
        'id': 'fabric-loader-0.16.9-1.20.1',
        'inheritsFrom': '1.20.1',
        'mainClass': 'net.fabricmc.loader.impl.launch.knot.KnotClient',
        'libraries': [
          {'name': 'net.fabricmc:fabric-loader:0.16.9'},
        ],
      });

      final merged = resolveInheritance(child, (id) {
        expect(id, '1.20.1');
        return parent;
      });

      // Without this the classpath asks for
      // `versions/fabric-loader-0.16.9-1.20.1/fabric-loader-0.16.9-1.20.1.jar`,
      // which no installer writes.
      expect(merged.jar, '1.20.1');
      expect(merged.mainClass, contains('KnotClient'));
      expect(
        merged.libraries.map((l) => l.name),
        containsAll([
          'com.example:parent:1.0',
          'net.fabricmc:fabric-loader:0.16.9',
        ]),
      );
    });
  });
}
