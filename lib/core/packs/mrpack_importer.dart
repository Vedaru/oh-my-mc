import 'dart:io';

import 'package:path/path.dart' as p;

import '../mods/zip_entry_reader.dart';
import '../net/cancellation.dart';
import 'mrpack.dart';

/// What an import put on disk.
class MrpackImportResult {
  const MrpackImportResult({
    required this.index,
    required this.installed,
    required this.skipped,
    required this.failed,
    required this.overrideCount,
  });

  final MrpackIndex index;
  final List<String> installed;
  final List<String> skipped;
  final Map<String, String> failed;

  /// Files copied out of `overrides/` and `client-overrides/`.
  final int overrideCount;
}

/// Imports a `.mrpack` into a game directory.
///
/// The manifest is read out of the zip and the mods are fetched by URL: a
/// `.mrpack` deliberately contains no jars, so "import" is a manifest apply, not
/// a copy. Overrides are unpacked last and win over downloads, which is what the
/// format specifies - a pack that ships a patched config expects that config.
class MrpackImporter {
  MrpackImporter({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  Future<MrpackImportResult> import(
    File pack, {
    required Directory gameDir,
    CancelToken? cancel,
    void Function(int done, int total, String label)? onProgress,
  }) async {
    final reader = await ZipEntryReader.open(pack);
    try {
      final manifest = await reader.readFirst(const ['modrinth.index.json']);
      if (manifest == null) {
        throw const FormatException(
          'not a Modrinth pack: no modrinth.index.json',
        );
      }
      final index = MrpackIndex.parse(manifest);

      final installed = <String>[];
      final skipped = <String>[];
      final failed = <String, String>{};
      final files = index.clientFiles.toList();

      for (var i = 0; i < files.length; i++) {
        final file = files[i];
        cancel?.throwIfCancelled('modpack import');
        // A pack path is relative and can climb; refusing those is the difference
        // between importing a pack and letting it write outside the instance.
        final target = _safeJoin(gameDir, file.path);
        if (target == null) {
          failed[file.path] = 'unsafe path in pack';
          continue;
        }
        onProgress?.call(i, files.length, file.path);

        if (File(target).existsSync()) {
          skipped.add(file.path);
          continue;
        }
        await Directory(p.dirname(target)).create(recursive: true);
        try {
          await _download(file, target, cancel: cancel);
          installed.add(file.path);
        } on Object catch (e) {
          failed[file.path] = '$e';
          final part = File('$target.part');
          if (part.existsSync()) part.deleteSync();
        }
      }

      // Overrides after downloads: the format says they win.
      var overrides = 0;
      for (final prefix in const ['overrides/', 'client-overrides/']) {
        for (final name in reader.names) {
          if (!name.startsWith(prefix) || name.endsWith('/')) continue;
          cancel?.throwIfCancelled('modpack overrides');
          final relative = name.substring(prefix.length);
          final target = _safeJoin(gameDir, relative);
          if (target == null) continue;
          final bytes = await reader.read(name);
          if (bytes == null) continue;
          await Directory(p.dirname(target)).create(recursive: true);
          await File(target).writeAsBytes(bytes, flush: true);
          overrides++;
        }
      }

      onProgress?.call(files.length, files.length, '');
      return MrpackImportResult(
        index: index,
        installed: installed,
        skipped: skipped,
        failed: failed,
        overrideCount: overrides,
      );
    } finally {
      await reader.close();
    }
  }

  /// Resolves [relative] under [root], or `null` if it escapes.
  static String? _safeJoin(Directory root, String relative) {
    if (relative.isEmpty) return null;
    final normalised = p.normalize(relative);
    if (p.isAbsolute(normalised) || normalised.startsWith('..')) return null;
    final target = p.normalize(p.join(root.path, normalised));
    return p.isWithin(root.path, target) ? target : null;
  }

  Future<void> _download(
    MrpackFile file,
    String target, {
    CancelToken? cancel,
  }) async {
    Object? lastError;
    // Mirrors are listed in preference order; a 404 from the first is normal for
    // packs exported against a CDN that has since moved.
    for (final url in file.downloads) {
      try {
        final request = await _client.getUrl(Uri.parse(url));
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          await response.drain<void>();
          lastError = HttpException('HTTP ${response.statusCode} from $url');
          continue;
        }
        final part = File('$target.part');
        final sink = part.openWrite();
        try {
          await response.pipe(sink);
        } finally {
          await sink.close();
        }
        cancel?.throwIfCancelled('modpack import');
        await part.rename(target);
        return;
      } on Object catch (e) {
        lastError = e;
      }
    }
    throw lastError ??
        StateError('no download mirror answered for ${file.path}');
  }

  void close() => _client.close(force: true);
}
