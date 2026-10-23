// Real-network check for the Modrinth path: resolve a mod that has a required
// dependency, download both into a temp folder, and print what landed.
//
// Not part of `flutter test` - it needs the network and a ~10 MB download. Run it
// when the API shapes are in doubt:
//
//   dart run tool/smoke_modrinth.dart [projectId]
//
// `iris` is the default because it depends on `sodium`, so a resolve that ignores
// dependencies fails visibly instead of silently succeeding.
import 'dart:io';

import 'package:oh_my_mc/core/mods/mod_installer.dart';
import 'package:oh_my_mc/core/mods/modrinth.dart';

Future<void> main(List<String> args) async {
  final projectId = args.isEmpty ? 'YL57xq9U' : args.first; // iris shaders
  const gameVersion = '1.20.1';
  const loader = 'fabric';

  final client = ModrinthClient();
  final installer = ModInstaller();
  final dir = Directory.systemTemp.createTempSync('modrinth-smoke');
  try {
    final search = await client.search(
      'shaders',
      gameVersion: gameVersion,
      loader: loader,
      limit: 3,
    );
    stdout.writeln('search: ${search.map((p) => p.title).join(', ')}');

    final plans = await client.resolve(
      projectId: projectId,
      title: search.isEmpty ? projectId : search.first.title,
      gameVersion: gameVersion,
      loader: loader,
    );
    for (final plan in plans) {
      stdout.writeln(
        'plan: ${plan.reason.padRight(8)} ${plan.projectId.padRight(10)} '
        '${plan.fileName}',
      );
    }

    final outcome = await installer.install(
      plans: plans,
      modsDir: dir.path,
      onProgress: (done, total, name) {
        if (name.isNotEmpty) stdout.writeln('  [$done/$total] $name');
      },
    );
    stdout.writeln(
      'installed: ${outcome.installed.length}, skipped: ${outcome.skipped.length}, '
      'failed: ${outcome.failed}',
    );
    for (final file in dir.listSync().whereType<File>()) {
      stdout.writeln('  ${file.uri.pathSegments.last}  ${file.lengthSync()} B');
    }
  } finally {
    installer.close();
    client.close();
    dir.deleteSync(recursive: true);
  }
}
