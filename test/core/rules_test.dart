import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/mc/host.dart';
import 'package:oh_my_mc/core/mc/rules.dart';

const _linux = RuleContext(os: HostOs.linux, arch: HostArch.x86_64);
const _win11 = RuleContext(
  os: HostOs.windows,
  arch: HostArch.x86_64,
  osVersion: '10.0.22631',
);
const _macArm = RuleContext(os: HostOs.osx, arch: HostArch.arm64);

List<Rule> rulesFrom(String json) =>
    parseRules(jsonDecode(json) as List<dynamic>)!;

void main() {
  group('absence of rules', () {
    test('null and empty both allow', () {
      expect(ruleAllows(null, _linux), isTrue);
      expect(ruleAllows(const [], _linux), isTrue);
    });
  });

  group('single rule', () {
    test('allow osx blocks linux', () {
      final rules = rulesFrom('[{"action":"allow","os":{"name":"osx"}}]');
      expect(ruleAllows(rules, _linux), isFalse);
      expect(ruleAllows(rules, _macArm), isTrue);
    });

    test('a lone disallow denies every host (deny-by-default)', () {
      // Mojang never emits this shape — real rules always carry an explicit
      // `{"action":"allow"}` base case, which the next test covers. Asserting
      // the strict reading keeps hand-written modloader metadata from
      // accidentally unblocking everything.
      final rules = rulesFrom('[{"action":"disallow","os":{"name":"osx"}}]');
      expect(ruleAllows(rules, _linux), isFalse);
      expect(ruleAllows(rules, _macArm), isFalse);
    });
  });

  group('last matching rule wins', () {
    test('allow-then-disallow osx blocks mac but allows linux', () {
      // 1.12.2 lwjgl-platform entry #1 has exactly this shape.
      final rules = rulesFrom(
        '[{"action":"allow"},{"action":"disallow","os":{"name":"osx"}}]',
      );
      expect(ruleAllows(rules, _linux), isTrue);
      expect(ruleAllows(rules, _macArm), isFalse);
    });

    test('disallow-then-allow osx allows mac only', () {
      final rules = rulesFrom(
        '[{"action":"disallow"},{"action":"allow","os":{"name":"osx"}}]',
      );
      expect(ruleAllows(rules, _macArm), isTrue);
      expect(ruleAllows(rules, _linux), isFalse);
    });
  });

  group('os arch', () {
    test('arch x86 does not match an x86_64 host', () {
      final rules = rulesFrom('[{"action":"allow","os":{"arch":"x86"}}]');
      expect(ruleAllows(rules, _linux), isFalse);
    });

    test('arch x86_64 matches an x86_64 host', () {
      final rules = rulesFrom('[{"action":"allow","os":{"arch":"x86_64"}}]');
      expect(ruleAllows(rules, _linux), isTrue);
    });
  });

  group('versionRange', () {
    test('26.3 ZGC rule: min 10.0.17134 matches Windows 11', () {
      final rules = rulesFrom(
        '[{"action":"allow","os":{"name":"windows",'
        '"versionRange":{"min":"10.0.17134"}}}]',
      );
      expect(ruleAllows(rules, _win11), isTrue);
    });

    test('max bound excludes newer Windows', () {
      final rules = rulesFrom(
        '[{"action":"allow","os":{"name":"windows",'
        '"versionRange":{"max":"10.0.17134"}}}]',
      );
      expect(ruleAllows(rules, _win11), isFalse);
    });

    test('unknown host version cannot satisfy a range', () {
      final rules = rulesFrom(
        '[{"action":"allow","os":{"name":"windows",'
        '"versionRange":{"min":"6.1"}}}]',
      );
      const noVersion = RuleContext(os: HostOs.windows, arch: HostArch.x86_64);
      expect(ruleAllows(rules, noVersion), isFalse);
    });
  });

  group('features', () {
    // Exactly the shape 1.20.1 / 26.3 use for `--demo`: a single allow gated on
    // a feature, with no base-case allow.
    final rules = rulesFrom(
      '[{"action":"allow","features":{"is_demo_user":true}}]',
    );

    test('false feature fails the gate', () {
      expect(ruleAllows(rules, _linux), isFalse);
    });

    test('true feature passes it', () {
      expect(
        ruleAllows(rules, _linux.copyWith(features: {'is_demo_user': true})),
        isTrue,
      );
    });
  });

  group('compareVersions', () {
    test('numeric, not lexical', () {
      expect(compareVersions('10.0.9', '10.0.17134'), lessThan(0));
      expect(compareVersions('10.0.17134', '10.0.9'), greaterThan(0));
      expect(compareVersions('10.0', '10.0.0'), 0);
    });
  });

  group('HostArch.fromToken', () {
    test('maps dart:io tokens', () {
      expect(HostArch.fromToken('x64'), HostArch.x86_64);
      expect(HostArch.fromToken('arm64'), HostArch.arm64);
      expect(HostArch.fromToken('aarch64'), HostArch.arm64);
      expect(HostArch.fromToken('ia32'), HostArch.x86);
    });
  });
}
