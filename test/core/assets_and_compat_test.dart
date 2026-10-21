import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/mc/arch_compat.dart';
import 'package:oh_my_mc/core/mc/asset_index.dart';
import 'package:oh_my_mc/core/mc/host.dart';
import 'package:oh_my_mc/core/mc/library_graph.dart';

import 'fixtures.dart';

const _linux = RuleContext(os: HostOs.linux, arch: HostArch.x86_64);
const _macArm = RuleContext(os: HostOs.osx, arch: HostArch.arm64);

void main() {
  group('asset layouts over real indexes', () {
    test('modern indexes are hashed with no virtual flag', () {
      for (final id in ['26.3', '1.20.1']) {
        final idx = loadAssetIndex(id);
        expect(idx.layout, AssetLayout.hashed, reason: id);
        expect(idx.objects, isNotEmpty, reason: id);
        for (final o in idx.objects.values.take(5)) {
          expect(o.hash, hasLength(40), reason: id);
          expect(o.objectPath, '${o.hash.substring(0, 2)}/${o.hash}');
        }
      }
    });

    test('1.6.4 is virtual', () {
      final idx = loadAssetIndex('1.6.4');
      expect(idx.layout, AssetLayout.virtual);
    });

    test('1.5.2 maps to resources', () {
      final idx = loadAssetIndex('1.5.2');
      expect(idx.layout, AssetLayout.legacyResources);
    });

    test('layout is read from the index, not guessed from the index id', () {
      // 1.20.1's index id is "5" and 26.3's is "34"; neither is "legacy", yet
      // both must parse as hashed. This is why id-sniffing is not used.
      expect(loadAssetIndex('1.20.1').layout, AssetLayout.hashed);
      expect(loadAssetIndex('26.3').layout, AssetLayout.hashed);
    });

    test('objects expose a resources.download.minecraft.net url', () {
      final o = loadAssetIndex('1.20.1').objects.values.first;
      expect(o.url, startsWith('https://resources.download.minecraft.net/'));
      expect(o.url, endsWith(o.hash));
    });

    test('sampled indexes report the true object count', () {
      final idx = loadAssetIndex('1.20.1');
      expect(idx.totalObjects, greaterThan(idx.objects.length));
      expect(idx.totalObjects, 3598);
    });

    test('distinct blobs collapse shared hashes', () {
      final idx = loadAssetIndex('26.3');
      expect(idx.distinctBlobs.length, lessThanOrEqualTo(idx.objects.length));
    });
  });

  group('launch blockers', () {
    test('LWJGL2 on Apple Silicon is reported with a remedy', () {
      final v = loadVersion('1.12.2');
      final graph = buildLibraryGraph(v, _macArm);
      final blockers = detectBlockers(v, graph, HostOs.osx, HostArch.arm64);

      final lwjgl = blockers.where(
        (b) => b.code == BlockerCode.lwjgl2OnArm64Mac,
      );
      expect(lwjgl, hasLength(1));
      expect(lwjgl.single.remedy.toLowerCase(), contains('rosetta'));
    });

    test('the same version is fine on x86_64', () {
      final v = loadVersion('1.12.2');
      final graph = buildLibraryGraph(v, _linux);
      final blockers = detectBlockers(v, graph, HostOs.linux, HostArch.x86_64);
      expect(
        blockers.where((b) => b.code == BlockerCode.lwjgl2OnArm64Mac),
        isEmpty,
      );
    });

    test('modern versions are not flagged on Apple Silicon', () {
      final v = loadVersion('26.3');
      final graph = buildLibraryGraph(v, _macArm);
      final blockers = detectBlockers(v, graph, HostOs.osx, HostArch.arm64);
      expect(
        blockers.where((b) => b.code == BlockerCode.lwjgl2OnArm64Mac),
        isEmpty,
      );
    });

    test('Java older than declared is reported', () {
      final v = loadVersion('1.20.1'); // needs 17
      final blocker = checkJava(v, 8);
      expect(blocker?.code, BlockerCode.javaTooOld);
      expect(blocker!.message, contains('17'));
      expect(checkJava(v, 17), isNull);
      expect(checkJava(v, 21), isNull);
    });

    test('an undetected Java major is not treated as too old', () {
      expect(checkJava(loadVersion('1.20.1'), null), isNull);
    });
  });

  group('graph completeness', () {
    test('26.3 resolves most of its libraries on linux', () {
      // 114 declared; the remainder are macOS/Windows-gated (objc-bridge,
      // SDL/OpenAL natives) or duplicate artifacts, so 66 on linux is expected.
      final graph = buildLibraryGraph(loadVersion('26.3'), _linux);
      expect(graph.classpath.length, greaterThan(60));
      expect(graph.classpath.length, lessThan(114));
    });

    test('every captured version yields a non-empty classpath on linux', () {
      for (final id in capturedVersions) {
        final graph = buildLibraryGraph(loadVersion(id), _linux);
        expect(
          graph.classpath,
          isNotEmpty,
          reason: '$id produced an empty classpath',
        );
        for (final f in graph.classpath) {
          expect(f.path, isNot(startsWith('/')), reason: '$id absolute path');
          expect(f.path, isNot(contains('..')), reason: '$id traversal');
        }
      }
    });
  });
}
