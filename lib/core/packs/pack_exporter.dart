import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../instance/instance.dart';

/// The launcher's own pack format: a zip with `oh-my-mc-pack.json` plus the
/// instance's game directory, minus everything rebuildable.
///
/// Deliberately the same shape as an `.mrpack` in spirit - a manifest and a
/// payload - but with the payload included: this is how a user moves an instance
/// to another machine or hands it to a friend, and depending on the original CDNs
/// still existing would make it a broken promise years later.
class PackExporter {
  PackExporter({this.includeSaves = true});

  /// Saves are the user's world data: included by default, because an export that
  /// silently drops them is worse than a larger file.
  final bool includeSaves;

  /// Directories that are either rebuilt by the installer or are logs. Copying
  /// `libraries/` alone would make a 400 MB zip of files the launcher re-downloads.
  static const excludedDirs = {
    'libraries',
    'assets',
    'versions',
    'logs',
    'crash-reports',
    'natives',
  };

  static const manifestName = 'oh-my-mc-pack.json';

  /// Writes [instance]'s game directory to [out].
  Future<int> export({
    required Instance instance,
    required Directory gameDir,
    required File out,
  }) async {
    final encoder = ZipFileEncoder()..create(out.path);

    try {
      final manifest = {
        'formatVersion': 1,
        'name': instance.name,
        'versionId': instance.versionId,
        'loader': instance.loader.name,
        'loaderVersion': instance.loaderVersion,
        'memoryMb': instance.memoryMb,
        'jvmArgs': instance.jvmArgs,
        'gameArgs': instance.gameArgs,
        'createdAt': instance.createdAt?.toIso8601String(),
      };
      final bytes = utf8.encode(
        const JsonEncoder.withIndent('  ').convert(manifest),
      );
      encoder.addArchiveFile(ArchiveFile(manifestName, bytes.length, bytes));

      var count = 1;
      if (!await gameDir.exists()) {
        await encoder.close();
        return count;
      }

      await for (final entity in gameDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final relative = p.relative(entity.path, from: gameDir.path);
        final top = p.split(relative).first;
        if (excludedDirs.contains(top)) continue;
        if (!includeSaves && top == 'saves') continue;

        final data = await entity.readAsBytes();
        encoder.addArchiveFile(ArchiveFile(relative, data.length, data));
        count++;
      }

      await encoder.close();
      return count;
    } on Object {
      // A half-written zip is not an export: remove it rather than leave the user
      // with a file that fails to import with no explanation.
      if (await out.exists()) await out.delete();
      rethrow;
    }
  }
}
