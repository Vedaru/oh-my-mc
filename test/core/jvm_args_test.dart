import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/mc/host.dart';
import 'package:oh_my_mc/core/mc/jvm_args.dart';

import 'fixtures.dart';

const _linux = RuleContext(os: HostOs.linux, arch: HostArch.x86_64);
const _win11 = RuleContext(
  os: HostOs.windows,
  arch: HostArch.x86_64,
  osVersion: '10.0.22631',
);
const _win7 = RuleContext(
  os: HostOs.windows,
  arch: HostArch.x86_64,
  osVersion: '6.1.7601',
);
const _mac = RuleContext(os: HostOs.osx, arch: HostArch.arm64);

const _vars = LaunchVariables(
  authPlayerName: 'Steve',
  versionName: '1.20.1',
  gameDirectory: '/games/mc',
  assetsRoot: '/games/mc/assets',
  assetIndexName: '5',
  authUuid: '00000000000000000000000000000000',
  authAccessToken: 'token',
  userType: 'msa',
  versionType: 'release',
  nativesDirectory: '/games/mc/versions/1.20.1/natives',
  classpath: '/a.jar:/b.jar',
);

void main() {
  group('placeholder expansion', () {
    test('expands every modern placeholder', () {
      expect(expandPlaceholders(r'${auth_player_name}', _vars), 'Steve');
      expect(expandPlaceholders(r'${assets_root}', _vars), '/games/mc/assets');
      expect(expandPlaceholders(r'${classpath}', _vars), '/a.jar:/b.jar');
      expect(
        expandPlaceholders(r'-Djava.library.path=${natives_directory}', _vars),
        '-Djava.library.path=/games/mc/versions/1.20.1/natives',
      );
    });

    test('legacy session placeholder maps onto the access token', () {
      expect(expandPlaceholders(r'${auth_session}', _vars), 'token');
    });

    test('unknown placeholders are left intact rather than blanked', () {
      expect(
        expandPlaceholders(r'${mystery_value}', _vars),
        r'${mystery_value}',
      );
    });

    test('strings without placeholders are returned untouched', () {
      expect(expandPlaceholders('-XX:+UseG1GC', _vars), '-XX:+UseG1GC');
    });
  });

  group('modern jvm arguments (26.3)', () {
    test('includes the classpath and natives wiring', () {
      final args = renderArguments(
        loadVersion('26.3'),
        ArgSide.jvm,
        _linux,
        _vars,
      );
      expect(args, contains('-cp'));
      expect(args, contains(_vars.classpath));
      expect(
        args,
        contains('-Djava.library.path=${_vars.nativesDirectory}/java'),
      );
      expect(args, contains('-XX:StackShadowPages=32'));
    });

    test('os-gated entries only appear on their platform', () {
      final linux = renderArguments(
        loadVersion('26.3'),
        ArgSide.jvm,
        _linux,
        _vars,
      );
      final mac = renderArguments(
        loadVersion('26.3'),
        ArgSide.jvm,
        _mac,
        _vars,
      );

      expect(linux.any((a) => a.contains('HeapDumpPath')), isFalse);
      expect(mac, contains('-XstartOnFirstThread'));
      expect(linux, isNot(contains('-XstartOnFirstThread')));
    });

    test('default-user-jvm is never passed to the game', () {
      final args = renderArguments(
        loadVersion('26.3'),
        ArgSide.jvm,
        _linux,
        _vars,
      );
      expect(args, isNot(contains('-Xmx4G')));
      expect(args, isNot(contains('-Xms2G')));
    });

    test('suggested defaults are exposed for the settings UI instead', () {
      final suggested = suggestedJvmDefaults(loadVersion('26.3'), _linux);
      expect(suggested, contains('-Xmx4G'));
      // Linux gets ZGC; the G1 block is the Windows-before-17134 branch.
      expect(suggested, contains('-XX:+UseZGC'));
      expect(suggested, isNot(contains('-XX:+UseG1GC')));
    });

    test('suggestion branches follow the Windows version range', () {
      final win11 = suggestedJvmDefaults(loadVersion('26.3'), _win11);
      expect(win11, contains('-XX:+UseZGC'));

      final win7 = suggestedJvmDefaults(loadVersion('26.3'), _win7);
      expect(win7, contains('-XX:+UseG1GC'));
      expect(win7, isNot(contains('-XX:+UseZGC')));
    });
  });

  group('game arguments', () {
    test('1.20.1 renders a usable modern command line', () {
      final args = renderArguments(
        loadVersion('1.20.1'),
        ArgSide.game,
        _linux,
        _vars,
      );
      expect(args, containsAllInOrder(['--username', 'Steve']));
      expect(args, containsAllInOrder(['--version', '1.20.1']));
      expect(args, containsAllInOrder(['--gameDir', '/games/mc']));
      expect(args, containsAllInOrder(['--assetIndex', '5']));
      expect(args, containsAllInOrder(['--accessToken', 'token']));
      expect(args, containsAllInOrder(['--userType', 'msa']));
    });

    test('feature-gated arguments are absent unless the feature is on', () {
      final off = renderArguments(
        loadVersion('1.20.1'),
        ArgSide.game,
        _linux,
        _vars,
      );
      expect(off, isNot(contains('--demo')));

      final on = renderArguments(
        loadVersion('1.20.1'),
        ArgSide.game,
        _linux.copyWith(features: {'is_demo_user': true}),
        _vars,
      );
      expect(on, contains('--demo'));
    });

    test('custom resolution expands both placeholders', () {
      final args = renderArguments(
        loadVersion('1.20.1'),
        ArgSide.game,
        _linux.copyWith(features: {'has_custom_resolution': true}),
        _vars,
      );
      // Placeholders we do not model stay visible rather than becoming empty.
      expect(args, contains('--width'));
      expect(args, contains(r'${resolution_width}'));
    });
  });

  group('legacy arguments', () {
    test('minecraftArguments split into tokens and expanded', () {
      final args = renderArguments(
        loadVersion('1.8.9'),
        ArgSide.game,
        _windows,
        _vars,
      );
      expect(args, containsAllInOrder(['--username', 'Steve']));
      expect(args, containsAllInOrder(['--assetsDir', '/games/mc/assets']));
      expect(args, contains('msa'));
      expect(
        args.every((a) => !a.contains(r'${')),
        isTrue,
        reason: 'no placeholder survives',
      );
    });

    test('legacy versions render no jvm arguments of their own', () {
      final args = renderArguments(
        loadVersion('1.8.9'),
        ArgSide.jvm,
        _linux,
        _vars,
      );
      expect(args, isEmpty);
    });
  });
}

const _windows = RuleContext(os: HostOs.windows, arch: HostArch.x86_64);
