// Real-network smoke test: plans a 1.20.1 install and fetches a small slice of
// it, verifying hashes from live Mojang metadata.
//
//   dart run tool/smoke_download.dart [version]
//
// Not part of the test suite: the tests are offline and fixture-driven. This
// exists to catch "the URL shape changed" and "the mirror mapping is wrong",
// which no fixture can.
import 'dart:io';

import 'package:oh_my_mc/core/mc/asset_index.dart';
import 'package:oh_my_mc/core/mc/host.dart';
import 'package:oh_my_mc/core/mc/install_plan.dart';
import 'package:oh_my_mc/core/mc/version_json.dart';
import 'package:oh_my_mc/core/net/downloader.dart';
import 'package:oh_my_mc/core/net/mirror.dart';
import 'package:oh_my_mc/core/net/progress.dart';
import 'package:oh_my_mc/core/net/version_manifest.dart';

Future<void> main(List<String> args) async {
  final versionId = args.isEmpty ? '1.20.1' : args.first;
  final preferMirror = args.contains('--mirror');
  final tmp = await Directory.systemTemp.createTemp('oh_my_mc_smoke');
  final paths = GamePaths(tmp.path);
  final client = HttpClient();

  try {
    stdout.writeln('manifest …');
    final mirrors = MirrorChain(
      order: preferMirror
          ? const [DownloadSource.bmclapi, DownloadSource.official]
          : const [DownloadSource.official, DownloadSource.bmclapi],
    );
    final service = VersionManifestService(
      cacheFile: File('${tmp.path}/manifest.json'),
      mirrors: mirrors,
    );
    final manifest = await service.load(forceRefresh: true);
    final entry = manifest.byId(versionId);
    if (entry == null) {
      stderr.writeln('no such version: $versionId');
      exitCode = 1;
      return;
    }
    stdout.writeln('  latest release: ${manifest.latestRelease}');
    stdout.writeln('  found: ${entry.id} (${entry.type})');

    stdout.writeln('version json …');
    final versionJson = await fetchJson(Uri.parse(entry.url), client);
    final version = VersionJson.fromJson(versionJson);
    stdout.writeln('  main class: ${version.mainClass}');
    stdout.writeln('  libraries: ${version.libraries.length}');
    stdout.writeln('  asset index: ${version.assetIndexName}');
    stdout.writeln(
      '  java major: ${version.javaVersion?.majorVersion ?? '(unset)'}',
    );

    // Asset index, so the plan includes real object hashes.
    AssetIndex? assets;
    final indexRef = version.assetIndex;
    if (indexRef != null) {
      final indexJson = await fetchJson(Uri.parse(indexRef.url), client);
      assets = AssetIndex.fromJson(indexJson);
      stdout.writeln('  asset objects: ${assets.distinctBlobs.length} unique');
    }

    final plan = planInstall(
      version: version,
      host: const RuleContext(os: HostOs.linux, arch: HostArch.x86_64),
      paths: paths,
      assetIndex: assets,
    );
    stdout.writeln('plan: ${describeInstall(plan)}');

    // One metadata file, two libraries, one asset object.
    final sample = <DownloadTask>[
      ...plan.tasks
          .where((t) => t.priority == DownloadPriority.metadata)
          .take(1),
      ...plan.tasks.where((t) => t.targetPath.contains('/libraries/')).take(2),
      ...plan.tasks
          .where((t) => t.targetPath.contains('/assets/objects/'))
          .take(1),
    ];

    stdout.writeln(
      '\ndownloading ${sample.length} of ${plan.fileCount} files …',
    );
    final downloader = FileDownloader(mirrors: mirrors);
    await for (final p in downloader.download(sample, concurrency: 4)) {
      stdout.write(
        '\r  ${p.filesDone}/${p.filesTotal}  '
        '${formatBytes(p.bytesDone)}  ${formatRate(p.bytesPerSecond)}  '
        '${formatEta(p.eta)}   ',
      );
    }
    downloader.close();
    stdout.writeln('\n');

    var ok = 0;
    for (final task in sample) {
      final file = File(task.targetPath);
      final exists = file.existsSync();
      final rightSize = exists && file.lengthSync() == task.size;
      stdout.writeln(
        '  ${exists && rightSize ? 'ok  ' : 'FAIL'} '
        '${task.targetPath.substring(tmp.path.length + 1)} '
        '(${formatBytes(task.size)})',
      );
      if (exists && rightSize) ok++;
    }
    stdout.writeln('\n$ok/${sample.length} files verified');
    if (ok != sample.length) exitCode = 1;
  } finally {
    client.close(force: true);
    await tmp.delete(recursive: true);
  }
}
