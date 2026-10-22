import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/install/verify.dart';
import 'package:oh_my_mc/core/install/version_installer.dart';
import 'package:oh_my_mc/core/mc/host.dart';
import 'package:oh_my_mc/core/mc/install_plan.dart';

/// Installs a real version from Mojang's servers.
///
/// Skipped unless `OH_MY_MC_NETWORK_TESTS=1`, because it downloads ~250 MB. It
/// lives in the normal test tree on purpose: the default run still *compiles* it,
/// so an API change breaks the gate immediately instead of leaving this file to
/// rot unnoticed until someone needs it. Only the download is skipped.
///
/// It exists because the synthetic fixture proves the *pipeline* while this
/// proves the *metadata still parses*: Mojang has changed asset index shapes and
/// natives layouts before, and only a real run catches that.
///
/// Run with: `OH_MY_MC_NETWORK_TESTS=1 flutter test test/core/install/network_install_test.dart`
void main() {
  final enabled = Platform.environment['OH_MY_MC_NETWORK_TESTS'] == '1';

  test(
    'installs 1.20.1 and verifies clean',
    () async {
      final tmp = await Directory.systemTemp.createTemp('install_1201');
      final paths = GamePaths(tmp.path);
      final installer = VersionInstaller(concurrency: 8);

      try {
        final result = await installer.install(
          versionId: '1.20.1',
          paths: paths,
          host: const RuleContext(os: HostOs.linux, arch: HostArch.x86_64),
        );

        expect(
          result.verification.isComplete,
          isTrue,
          reason: 'verifyInstall reported ${result.verification}',
        );
        expect(result.plan.fileCount, greaterThan(500));
        expect(File(paths.versionJson('1.20.1')).existsSync(), isTrue);
        expect(File(paths.versionJar('1.20.1')).existsSync(), isTrue);

        // 1.20.1 uses the modern hashed layout: no virtual copies, but the
        // objects must be on disk.
        expect(result.assets.layout.name, 'hashed');
        final objects = Directory(paths.assetObjects);
        expect(objects.existsSync(), isTrue);
        expect(objects.listSync().length, greaterThan(10));

        // Re-check with hashes: size alone can lie.
        final deep = await verifyInstall(result.plan, checkHashes: true);
        expect(
          deep.isComplete,
          isTrue,
          reason: 'hash verification found ${deep.problems.take(3)}',
        );
      } finally {
        installer.close();
        if (tmp.existsSync()) await tmp.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
    skip: enabled
        ? false
        : 'set OH_MY_MC_NETWORK_TESTS=1 to run the ~250 MB real install',
  );
}
