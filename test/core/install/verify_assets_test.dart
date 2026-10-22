import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/install/asset_layout.dart';
import 'package:oh_my_mc/core/install/verify.dart';
import 'package:oh_my_mc/core/mc/asset_index.dart';
import 'package:oh_my_mc/core/mc/install_plan.dart';
import 'package:oh_my_mc/core/net/cancellation.dart';
import 'package:oh_my_mc/core/net/downloader.dart';

InstallPlan planFor(GamePaths paths, List<DownloadTask> tasks) => InstallPlan(
  versionId: 'test',
  paths: paths,
  tasks: tasks,
  totalBytes: tasks.fold(0, (s, t) => s + t.size),
  stages: const {},
  missingNatives: const [],
);

DownloadTask taskTo(String path, String content) => DownloadTask(
  url: Uri.parse('http://example.invalid/x'),
  targetPath: path,
  sha1: '',
  size: utf8.encode(content).length,
);

AssetIndex indexWith({
  required AssetLayout layout,
  required Map<String, String> nameToHash,
}) => AssetIndex(
  objects: {
    for (final e in nameToHash.entries)
      e.key: AssetObject(hash: e.value, size: 4),
  },
  layout: layout,
  totalObjects: nameToHash.length,
);

void main() {
  late Directory tmp;
  late GamePaths paths;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('verify_assets_test');
    paths = GamePaths(tmp.path);
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  group('verifyInstall', () {
    test('an empty problem list means complete', () async {
      final f = File('${tmp.path}/a.jar')..writeAsStringSync('1234');
      final report = await verifyInstall(
        planFor(paths, [taskTo(f.path, '1234')]),
      );
      expect(report.isComplete, isTrue);
      expect(report.checkedFiles, 1);
      expect(report.checkedBytes, 4);
    });

    test('a missing file is reported, not thrown', () async {
      final report = await verifyInstall(
        planFor(paths, [taskTo('${tmp.path}/nope.jar', '1234')]),
      );
      expect(report.isComplete, isFalse);
      expect(report.problems.single.reason, VerifyReason.missing);
      expect(report.missing.single, endsWith('nope.jar'));
    });

    test('a truncated file is wrongSize, not corrupt', () async {
      final f = File('${tmp.path}/short.jar')..writeAsStringSync('12');
      final report = await verifyInstall(
        planFor(paths, [taskTo(f.path, '1234')]),
      );
      expect(report.problems.single.reason, VerifyReason.wrongSize);
      expect(report.problems.single.expected, '4');
      expect(report.problems.single.actual, '2');
    });

    test('size-only checking does not read bytes', () async {
      final content = '1234';
      final f = File('${tmp.path}/a.jar')..writeAsStringSync(content);
      final task = DownloadTask(
        url: Uri.parse('http://example.invalid/x'),
        targetPath: f.path,
        sha1: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        size: 4,
      );

      final report = await verifyInstall(planFor(paths, [task]));
      expect(
        report.isComplete,
        isTrue,
        reason: 'size matches and hashing was not requested',
      );
    });

    test('with checkHashes, a size-correct wrong body is corrupt', () async {
      final f = File('${tmp.path}/a.jar')..writeAsStringSync('evil');
      final task = DownloadTask(
        url: Uri.parse('http://example.invalid/x'),
        targetPath: f.path,
        sha1: 'aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d', // sha1('hello')
        size: 4,
      );

      final report = await verifyInstall(
        planFor(paths, [task]),
        checkHashes: true,
      );
      expect(report.problems.single.reason, VerifyReason.corrupt);
    });

    test('with checkHashes, a correct file passes', () async {
      final f = File('${tmp.path}/a.jar')..writeAsStringSync('hello');
      final task = DownloadTask(
        url: Uri.parse('http://example.invalid/x'),
        targetPath: f.path,
        sha1: 'aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d',
        size: 5,
      );
      final report = await verifyInstall(
        planFor(paths, [task]),
        checkHashes: true,
      );
      expect(report.isComplete, isTrue);
    });

    test('mixed results report every problem', () async {
      final good = File('${tmp.path}/good.jar')..writeAsStringSync('1234');
      final short = File('${tmp.path}/short.jar')..writeAsStringSync('1');
      final report = await verifyInstall(
        planFor(paths, [
          taskTo(good.path, '1234'),
          taskTo(short.path, '1234'),
          taskTo('${tmp.path}/gone.jar', '1234'),
        ]),
      );
      expect(report.problems.length, 2);
      expect(report.checkedFiles, 2);
    });
  });

  group('materializeAssets', () {
    void putObject(String hash, String body) {
      final f = File(paths.assetObject(hash))
        ..createSync(recursive: true)
        ..writeAsStringSync(body);
      expect(f.existsSync(), isTrue);
    }

    test('hashed layout copies nothing', () async {
      final result = await materializeAssets(
        index: indexWith(
          layout: AssetLayout.hashed,
          nameToHash: {'a/b': 'aa11'},
        ),
        paths: paths,
        indexId: '5',
      );
      expect(result.copies, 0);
      expect(result.neededWork, isFalse);
      expect(Directory(paths.virtualAssets).existsSync(), isFalse);
    });

    test('virtual layout copies objects under virtual/<id>', () async {
      putObject('aabbccdd', 'sound-bytes');
      final result = await materializeAssets(
        index: indexWith(
          layout: AssetLayout.virtual,
          nameToHash: {'minecraft/sounds/step.ogg': 'aabbccdd'},
        ),
        paths: paths,
        indexId: 'legacy',
      );

      final copied = File(
        '${paths.virtualAssets}/legacy/minecraft/sounds/step.ogg',
      );
      expect(copied.existsSync(), isTrue);
      expect(copied.readAsStringSync(), 'sound-bytes');
      expect(result.copies, 1);
      expect(result.failures, isEmpty);
    });

    test('legacyResources layout copies into <root>/resources', () async {
      putObject('11223344', 'tex');
      await materializeAssets(
        index: indexWith(
          layout: AssetLayout.legacyResources,
          nameToHash: {'title/bg.png': '11223344'},
        ),
        paths: paths,
        indexId: 'pre16',
      );

      expect(
        File('${paths.legacyResources}/title/bg.png').readAsStringSync(),
        'tex',
      );
    });

    test('one blob under two names is copied twice, correctly', () async {
      putObject('99999999', 'shared');
      final result = await materializeAssets(
        index: indexWith(
          layout: AssetLayout.virtual,
          nameToHash: {'a/one.ogg': '99999999', 'a/two.ogg': '99999999'},
        ),
        paths: paths,
        indexId: 'v',
      );

      expect(result.copies, 2);
      expect(
        File('${paths.virtualAssets}/v/a/one.ogg').readAsStringSync(),
        'shared',
      );
      expect(
        File('${paths.virtualAssets}/v/a/two.ogg').readAsStringSync(),
        'shared',
      );
    });

    test('a missing object is reported rather than thrown', () async {
      final result = await materializeAssets(
        index: indexWith(
          layout: AssetLayout.virtual,
          nameToHash: {'a/missing.ogg': 'deadbeef'},
        ),
        paths: paths,
        indexId: 'v',
      );
      expect(result.failures, ['a/missing.ogg']);
      expect(result.copies, 0);
    });

    test('a second run does not rewrite up-to-date copies', () async {
      putObject('cafe1111', 'bytes');
      final index = indexWith(
        layout: AssetLayout.virtual,
        nameToHash: {'x/y.ogg': 'cafe1111'},
      );

      await materializeAssets(index: index, paths: paths, indexId: 'v');
      final target = File('${paths.virtualAssets}/v/x/y.ogg');
      final firstWrite = target.lastModifiedSync();

      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await materializeAssets(index: index, paths: paths, indexId: 'v');

      expect(
        target.lastModifiedSync(),
        firstWrite,
        reason: 'an unchanged copy must not be rewritten on reinstall',
      );
    });

    test('a traversal-shaped index key is refused, not written', () async {
      // The index is a downloaded file: a poisoned or MITM'd asset index is the
      // realistic vector, and its keys go straight into a path join.
      putObject('ffff0000', 'pwned');
      await expectLater(
        materializeAssets(
          index: indexWith(
            layout: AssetLayout.virtual,
            nameToHash: {'../../escaped.ogg': 'ffff0000'},
          ),
          paths: paths,
          indexId: 'v',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(File('${tmp.path}/escaped.ogg').existsSync(), isFalse);
      expect(File('${tmp.parent.path}/escaped.ogg').existsSync(), isFalse);
    });

    test('an absolute index key is refused', () async {
      putObject('ffff1111', 'pwned');
      // Inside this test's temp dir, not /tmp: a shared path makes the
      // assertion depend on whether an earlier failing run left a file behind.
      final target = '${tmp.path}/absolute-asset-pwned.ogg';
      await expectLater(
        materializeAssets(
          index: indexWith(
            layout: AssetLayout.virtual,
            nameToHash: {target: 'ffff1111'},
          ),
          paths: paths,
          indexId: 'v',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(File(target).existsSync(), isFalse);
    });

    test('cancellation stops copying', () async {
      putObject('aaaa0000', 'x');
      putObject('bbbb0000', 'y');
      final cancel = CancelToken()..cancel();

      await expectLater(
        materializeAssets(
          index: indexWith(
            layout: AssetLayout.virtual,
            nameToHash: {'a.ogg': 'aaaa0000', 'b.ogg': 'bbbb0000'},
          ),
          paths: paths,
          indexId: 'v',
          cancel: cancel,
        ),
        throwsA(isA<CancelledException>()),
      );
    });
  });
}
