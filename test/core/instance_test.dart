import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/instance/instance.dart';

Instance instance({
  String id = 'a',
  String name = 'A',
  String versionId = '1.20.1',
  LoaderKind loader = LoaderKind.vanilla,
  String? loaderVersion,
  IsolationKind isolation = IsolationKind.shareLibraries,
  String? javaPath,
  int? memoryMb,
  List<String> jvmArgs = const [],
  List<String> gameArgs = const [],
  DateTime? lastPlayedAt,
  Duration totalPlaytime = Duration.zero,
}) => Instance(
  id: id,
  name: name,
  versionId: versionId,
  loader: loader,
  loaderVersion: loaderVersion,
  isolation: isolation,
  javaPath: javaPath,
  memoryMb: memoryMb,
  jvmArgs: jvmArgs,
  gameArgs: gameArgs,
  lastPlayedAt: lastPlayedAt,
  totalPlaytime: totalPlaytime,
);

void main() {
  group('serialization', () {
    test('a fully populated instance survives a round trip', () {
      final original = Instance(
        id: 'fabric-1-20-1',
        name: 'Fabric 主实例',
        versionId: '1.20.1',
        loader: LoaderKind.fabric,
        loaderVersion: '0.15.2',
        isolation: IsolationKind.isolated,
        javaPath: '/opt/jdk-17/bin/java',
        memoryMb: 4096,
        jvmArgs: const ['-XX:+UseG1GC'],
        gameArgs: const ['--fullscreen'],
        createdAt: DateTime.utc(2026, 1, 2, 3, 4),
        lastPlayedAt: DateTime.utc(2026, 5, 6, 7, 8),
        totalPlaytime: const Duration(hours: 3, minutes: 12),
      );

      final restored = Instance.fromJson(original.toJson());

      expect(restored, original);
      expect(
        restored.name,
        'Fabric 主实例',
        reason:
            'non-ASCII is legal in the '
            'display name; only the directory name is slugified',
      );
      expect(restored.totalPlaytime, const Duration(hours: 3, minutes: 12));
      expect(restored.lastPlayedAt, DateTime.utc(2026, 5, 6, 7, 8));
    });

    test('defaults are omitted from JSON but restored on read', () {
      final json = instance().toJson();

      expect(json.containsKey('loaderVersion'), isFalse);
      expect(json.containsKey('memoryMb'), isFalse);
      expect(json.containsKey('jvmArgs'), isFalse);
      expect(json.containsKey('totalPlaytimeSeconds'), isFalse);

      final restored = Instance.fromJson(json);
      expect(restored.memoryMb, isNull);
      expect(restored.jvmArgs, isEmpty);
      expect(restored.totalPlaytime, Duration.zero);
    });

    test('an unknown loader or isolation name falls back, it does not throw', () {
      // A config written by a future build, or edited by hand. Losing the whole
      // instance over one unrecognised word would be worse than the fallback.
      final restored = Instance.fromJson({
        'id': 'x',
        'name': 'X',
        'versionId': '1.20.1',
        'loader': 'quilt-plus',
        'isolation': 'holographic',
      });

      expect(restored.loader, LoaderKind.vanilla);
      expect(restored.isolation, IsolationKind.shareLibraries);
      expect(restored.id, 'x');
    });

    test('a missing id is a parse error, not a guessed identity', () {
      expect(
        () => Instance.fromJson({'name': 'X', 'versionId': '1.20.1'}),
        throwsFormatException,
        reason: 'an instance without an id cannot be addressed or launched',
      );
      expect(
        () => Instance.fromJson({'id': '   ', 'name': 'X'}),
        throwsFormatException,
      );
    });

    test('non-string entries in an argument list are dropped, not fatal', () {
      final restored = Instance.fromJson({
        'id': 'x',
        'name': 'X',
        'versionId': '1.20.1',
        'jvmArgs': ['-Xmx2G', 7, null, '-Dfoo=bar'],
      });

      expect(restored.jvmArgs, ['-Xmx2G', '-Dfoo=bar']);
    });
  });

  group('copyWith', () {
    test('changes only the named field', () {
      final original = instance(
        loader: LoaderKind.forge,
        loaderVersion: '47.2.0',
        memoryMb: 2048,
        javaPath: '/jdk/bin/java',
      );

      final renamed = original.copyWith(name: 'Renamed');

      expect(renamed.name, 'Renamed');
      expect(renamed.versionId, original.versionId);
      expect(renamed.loader, LoaderKind.forge);
      expect(renamed.loaderVersion, '47.2.0');
      expect(renamed.memoryMb, 2048);
      expect(renamed.javaPath, '/jdk/bin/java');
      expect(renamed.id, original.id, reason: 'the directory must not move');
    });

    test('a nullable field cannot be cleared by passing null', () {
      // This is the trap: `copyWith(memoryMb: null)` reads as "unset", but with a
      // plain `??` it means "keep". An explicit flag is required, or the user
      // can never go back to the global default.
      final original = instance(memoryMb: 4096, javaPath: '/jdk/java');

      expect(original.copyWith(memoryMb: null).memoryMb, 4096);
      expect(
        original.copyWith(memoryMb: null, clearMemoryMb: true).memoryMb,
        isNull,
      );
      expect(original.copyWith(clearJavaPath: true).javaPath, isNull);
    });

    test('clearing a loader version leaves the loader kind alone', () {
      final forge = instance(loader: LoaderKind.forge, loaderVersion: '47.2.0');
      final cleared = forge.copyWith(clearLoaderVersion: true);

      expect(cleared.loaderVersion, isNull);
      expect(cleared.loader, LoaderKind.forge);
    });

    test('lists are replaced, not aliased', () {
      final args = ['-Xmx2G'];
      final original = instance(jvmArgs: args);
      final updated = original.copyWith(jvmArgs: ['-Xmx4G']);

      expect(original.jvmArgs, ['-Xmx2G']);
      expect(updated.jvmArgs, ['-Xmx4G']);
    });
  });

  group('displayName', () {
    test('falls back to the version when the name is blank', () {
      expect(instance(name: '', versionId: '1.20.1').displayName, '1.20.1');
      expect(instance(name: '   ', versionId: '1.19.4').displayName, '1.19.4');
      expect(instance(name: 'Mine', versionId: '1.20.1').displayName, 'Mine');
    });
  });

  group('slugify', () {
    test('lowercases and joins words with a single dash', () {
      expect(slugify('My Instance'), 'my-instance');
      expect(slugify('My   Instance'), 'my-instance');
      expect(slugify('  leading and trailing  '), 'leading-and-trailing');
    });

    test('keeps digits, which version names need', () {
      expect(slugify('1.20.1'), '1-20-1');
      expect(slugify('Forge 47.2.0'), 'forge-47-2-0');
    });

    test('drops everything that is not ASCII alphanumeric', () {
      // CJK, dots, quotes and a path separator all become separators; the
      // display name keeps the original text.
      expect(slugify('我的世界'), 'instance');
      expect(slugify('a/b\\c'), 'a-b-c');
      expect(slugify('../../etc/passwd'), 'etc-passwd');
    });

    test('never yields an empty or dot-only name', () {
      for (final input in ['', '   ', '...', '///', '世界']) {
        final slug = slugify(input);
        expect(
          slug,
          isNotEmpty,
          reason: 'input "$input" produced an empty slug',
        );
        expect(slug, isNot('.'));
        expect(slug, isNot('..'));
        expect(slug.contains('/'), isFalse);
      }
    });

    test('a traversal attempt cannot escape the instances directory', () {
      // The slug goes into a path; `..` must not survive.
      for (final input in ['..', '../..', 'a/../b']) {
        expect(
          slugify(input).contains('..'),
          isFalse,
          reason: 'input "$input"',
        );
      }
    });
  });

  group('uniqueSlug', () {
    test('returns the slug when it is free', () {
      expect(uniqueSlug('mine', ['other']), 'mine');
      expect(uniqueSlug('mine', const []), 'mine');
    });

    test('suffixes from 2 and stops at the first gap', () {
      expect(uniqueSlug('mine', ['mine']), 'mine-2');
      expect(uniqueSlug('mine', ['mine', 'mine-2']), 'mine-3');
      // A gap is reused rather than counting past it: after deleting mine-2, the
      // next instance should take mine-2, not mine-4.
      expect(uniqueSlug('mine', ['mine', 'mine-3']), 'mine-2');
    });
  });

  group('file format', () {
    test('a list round trips through encode/decode', () {
      final instances = [
        instance(id: 'a', name: 'A'),
        instance(id: 'b', name: 'B', loader: LoaderKind.neoforge),
      ];

      final decoded = decodeInstances(encodeInstances(instances));

      expect(decoded.skipped, 0);
      expect(decoded.instances, instances);
    });

    test('the file carries a version so a future format can migrate', () {
      final text = encodeInstances([instance()]);
      expect(text, contains('"version": 1'));
    });

    test('one broken entry does not cost the other instances', () {
      // The realistic corruption: a hand edit, or a truncated write followed by
      // an append.
      final text = '''
{
  "version": 1,
  "instances": [
    {"id": "good-1", "name": "Good", "versionId": "1.20.1"},
    {"name": "no id at all", "versionId": "1.20.1"},
    "not even an object",
    {"id": "good-2", "name": "Also good", "versionId": "1.19.4"}
  ]
}''';

      final decoded = decodeInstances(text);

      expect(decoded.instances.map((i) => i.id), ['good-1', 'good-2']);
      expect(
        decoded.skipped,
        2,
        reason: 'the caller must be able to tell the user something was lost',
      );
    });

    test('a duplicate id keeps the first and reports the second', () {
      final text = '''
{"version": 1, "instances": [
  {"id": "same", "name": "First", "versionId": "1.20.1"},
  {"id": "same", "name": "Second", "versionId": "1.19.4"}
]}''';

      final decoded = decodeInstances(text);

      expect(decoded.instances.single.name, 'First');
      expect(
        decoded.skipped,
        1,
        reason:
            'two instances sharing a directory '
            'would overwrite each other',
      );
    });

    test('unparseable text yields an empty list and a skip count', () {
      for (final text in ['', 'not json', '[]', '{"instances": "nope"}']) {
        final decoded = decodeInstances(text);
        expect(decoded.instances, isEmpty, reason: 'input "$text"');
        expect(
          decoded.skipped,
          greaterThanOrEqualTo(1),
          reason: 'input "$text"',
        );
      }
    });
  });

  group('value semantics', () {
    test('equal fields mean equal instances', () {
      expect(instance(), instance());
      expect(instance().hashCode, instance().hashCode);
      expect(instance(name: 'B'), isNot(instance(name: 'A')));
    });

    test('argument lists are compared by content', () {
      expect(
        instance(jvmArgs: const ['-Xmx2G']),
        instance(jvmArgs: const ['-Xmx2G']),
      );
      expect(
        instance(jvmArgs: const ['-Xmx2G']),
        isNot(instance(jvmArgs: const ['-Xmx4G'])),
      );
    });
  });
}
