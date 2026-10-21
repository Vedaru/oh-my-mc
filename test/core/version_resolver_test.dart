import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/mc/host.dart';
import 'package:oh_my_mc/core/mc/library_graph.dart';
import 'package:oh_my_mc/core/mc/version_json.dart';
import 'package:oh_my_mc/core/mc/version_resolver.dart';

import 'fixtures.dart';

const _linux = RuleContext(os: HostOs.linux, arch: HostArch.x86_64);

Map<String, dynamic> minimal(String id, {String? inheritsFrom}) => {
  'id': id,
  'type': 'release',
  'mainClass': 'net.minecraft.client.main.Main',
  'inheritsFrom': ?inheritsFrom,
  'libraries': <dynamic>[],
};

VersionJson parse(Map<String, dynamic> json) =>
    VersionJson.fromJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>);

void main() {
  group('inheritance', () {
    test('returns the version untouched when it has no parent', () {
      final v = loadVersion('1.20.1');
      final resolved = resolveInheritance(v, (_) => null);
      expect(resolved.id, v.id);
      expect(resolved.libraries, hasLength(v.libraries.length));
    });

    test('child mainClass wins over parent', () {
      final parent = minimal('1.20.1')
        ..['mainClass'] = 'parent.Main'
        ..['libraries'] = [
          {'name': 'com.example:parent-lib:1.0.0'},
        ];
      final child = minimal('fabric-loader-0.15', inheritsFrom: '1.20.1')
        ..['mainClass'] = 'net.fabricmc.loader.impl.launch.knot.KnotClient'
        ..['libraries'] = [
          {'name': 'net.fabricmc:fabric-loader:0.15.0'},
        ];

      final resolved = resolveInheritance(
        parse(child),
        (id) => id == '1.20.1' ? parse(parent) : null,
      );

      expect(resolved.mainClass, contains('KnotClient'));
      expect(
        resolved.libraries.map((l) => l.name),
        containsAll([
          'com.example:parent-lib:1.0.0',
          'net.fabricmc:fabric-loader:0.15.0',
        ]),
      );
    });

    test(
      'child library supersedes the parent version of the same artifact',
      () {
        Map<String, dynamic> asmLib(String version) => {
          'name': 'org.ow2.asm:asm:$version',
          'downloads': {
            'artifact': {
              'path': 'org/ow2/asm/asm/$version/asm-$version.jar',
              'url': 'https://example.invalid/asm-$version.jar',
              'sha1': '0' * 40,
              'size': 1,
            },
          },
        };

        final parent = minimal('1.20.1')..['libraries'] = [asmLib('9.3')];
        final child = minimal('forge-47', inheritsFrom: '1.20.1')
          ..['libraries'] = [asmLib('9.5')];

        final resolved = resolveInheritance(
          parse(child),
          (id) => id == '1.20.1' ? parse(parent) : null,
        );

        expect(
          resolved.libraries,
          hasLength(2),
          reason: 'both survive merging',
        );
        final graph = buildLibraryGraph(resolved, _linux);
        expect(graph.classpath, hasLength(1), reason: 'dedupe keeps the child');
        expect(graph.classpath.single.path, contains('9.5'));
      },
    );

    test('three-level chains keep the near ancestor', () {
      final base = minimal('1.20.1')
        ..['libraries'] = [
          {'name': 'base:lib:1.0'},
        ];
      final middle = minimal('forge', inheritsFrom: '1.20.1')
        ..['libraries'] = [
          {'name': 'middle:lib:1.0'},
        ];
      final leaf = minimal('forge-instance', inheritsFrom: 'forge')
        ..['libraries'] = [
          {'name': 'leaf:lib:1.0'},
        ];

      final byId = {
        '1.20.1': parse(base),
        'forge': parse(middle),
        'forge-instance': parse(leaf),
      };
      final resolved = resolveInheritance(
        byId['forge-instance']!,
        (id) => byId[id],
      );

      expect(resolved.id, 'forge-instance');
      expect(
        resolved.libraries.map((l) => l.group),
        containsAll(['base', 'middle', 'leaf']),
      );
    });

    test('arguments concatenate parent-then-child', () {
      final parent = minimal('1.20.1')
        ..['arguments'] = {
          'game': ['--username', r'${auth_player_name}'],
          'jvm': ['-cp', r'${classpath}'],
        };
      final child = minimal('fabric', inheritsFrom: '1.20.1')
        ..['arguments'] = {
          'game': ['--fabricFlag'],
        };

      final resolved = resolveInheritance(
        parse(child),
        (id) => id == '1.20.1' ? parse(parent) : null,
      );

      expect(resolved.arguments.game.map((e) => e.value.single), [
        '--username',
        r'${auth_player_name}',
        '--fabricFlag',
      ]);
      expect(resolved.arguments.jvm.map((e) => e.value.single), [
        '-cp',
        r'${classpath}',
      ]);
    });

    test('a missing parent is a hard error, not a silent empty merge', () {
      final child = minimal('orphan', inheritsFrom: 'does-not-exist');
      expect(
        () => resolveInheritance(parse(child), (_) => null),
        throwsA(isA<StateError>()),
      );
    });

    test('an inheritance cycle fails instead of hanging', () {
      final a = minimal('a', inheritsFrom: 'b');
      final b = minimal('b', inheritsFrom: 'a');
      final byId = {'a': parse(a), 'b': parse(b)};
      expect(
        () => resolveInheritance(byId['a']!, (id) => byId[id]),
        throwsA(isA<StateError>()),
      );
    });

    test('legacy minecraftArguments are inherited when the child has none', () {
      final parent = minimal('1.12.2')
        ..['minecraftArguments'] = '--username \${auth_player_name}';
      final child = minimal('forge-1.12.2', inheritsFrom: '1.12.2');

      final resolved = resolveInheritance(
        parse(child),
        (id) => id == '1.12.2' ? parse(parent) : null,
      );
      expect(resolved.minecraftArguments, contains('--username'));
    });
  });
}
