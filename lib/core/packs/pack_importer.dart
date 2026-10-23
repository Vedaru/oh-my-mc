import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../instance/instance.dart';
import '../mods/zip_entry_reader.dart';
import 'mrpack.dart';
import 'mrpack_importer.dart';
import 'pack_exporter.dart';

enum PackKind { mrpack, launcher }

/// Just enough of a pack to create an instance for it, before any file is
/// written: the name and the version it needs.
class PackHeader {
  const PackHeader({
    required this.kind,
    required this.name,
    required this.gameVersion,
    required this.loader,
    this.loaderVersion,
  });

  final PackKind kind;
  final String name;
  final String gameVersion;
  final LoaderKind loader;
  final String? loaderVersion;
}

/// What an import found and wrote, whichever format it was.
class PackImport {
  const PackImport({
    required this.kind,
    required this.name,
    required this.gameVersion,
    required this.loader,
    required this.loaderVersion,
    required this.written,
    required this.failed,
  });

  final PackKind kind;
  final String name;
  final String gameVersion;
  final LoaderKind loader;
  final String? loaderVersion;

  /// Paths written, relative to the game directory.
  final List<String> written;
  final Map<String, String> failed;
}

/// One entry point for both formats, because to the user "import a pack" is one
/// action and the extension is not the interesting part.
///
/// The format is detected from the manifest inside the zip, not from the file
/// name: a `.mrpack` renamed to `.zip` is still an `.mrpack`, and Modrinth's own
/// site serves both.
class PackImporter {
  PackImporter({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  /// Reads the manifest without writing anything.
  ///
  /// The instance has to exist before the files can land in it, and the instance
  /// needs the pack's name - so the header is read first, the instance created
  /// second, and only then does the import run.
  Future<PackHeader> inspect(File pack) async {
    final reader = await ZipEntryReader.open(pack);
    try {
      final mrpack = await reader.readFirst(const ['modrinth.index.json']);
      if (mrpack != null) {
        final index = MrpackIndex.parse(mrpack);
        return PackHeader(
          kind: PackKind.mrpack,
          name: index.name,
          gameVersion: index.minecraft,
          loader: index.loader,
          loaderVersion: index.loaderVersion,
        );
      }
      final own = await reader.readFirst(const [PackExporter.manifestName]);
      if (own == null) {
        throw const FormatException(
          'not a pack: neither modrinth.index.json nor ${PackExporter.manifestName}',
        );
      }
      final manifest = jsonDecode(own) as Map<String, dynamic>;
      return PackHeader(
        kind: PackKind.launcher,
        name:
            manifest['name'] as String? ??
            p.basenameWithoutExtension(pack.path),
        gameVersion: manifest['versionId'] as String? ?? '',
        loader: LoaderKind.values.firstWhere(
          (kind) => kind.name == manifest['loader'],
          orElse: () => LoaderKind.vanilla,
        ),
        loaderVersion: manifest['loaderVersion'] as String?,
      );
    } finally {
      await reader.close();
    }
  }

  Future<PackImport> import(
    File pack, {
    required Directory gameDir,
    void Function(int done, int total, String label)? onProgress,
  }) async {
    await gameDir.create(recursive: true);

    final reader = await ZipEntryReader.open(pack);
    try {
      final hasMrpack = reader.names.contains('modrinth.index.json');
      final hasLauncherPack = reader.names.contains(PackExporter.manifestName);

      if (!hasMrpack && !hasLauncherPack) {
        throw const FormatException(
          'not a pack: neither modrinth.index.json nor ${PackExporter.manifestName}',
        );
      }

      if (hasMrpack) {
        // Close this handle first: the Modrinth importer opens the same file.
        final mrpack = await reader.readFirst(const ['modrinth.index.json']);
        final index = MrpackIndex.parse(mrpack!);
        return await _importMrpack(index, pack, gameDir, onProgress);
      }

      final manifestText = await reader.readFirst(const [
        PackExporter.manifestName,
      ]);
      final manifest = jsonDecode(manifestText!) as Map<String, dynamic>;
      final written = <String>[];
      final failed = <String, String>{};

      final entries = [
        for (final name in reader.names)
          if (name != PackExporter.manifestName && !name.endsWith('/')) name,
      ];
      for (var i = 0; i < entries.length; i++) {
        final name = entries[i];
        final target = _safeJoin(gameDir, name);
        if (target == null) {
          failed[name] = 'unsafe path in pack';
          continue;
        }
        onProgress?.call(i, entries.length, name);
        final bytes = await reader.read(name);
        if (bytes == null) {
          failed[name] = 'unreadable entry';
          continue;
        }
        await Directory(p.dirname(target)).create(recursive: true);
        await File(target).writeAsBytes(bytes, flush: true);
        written.add(name);
      }
      onProgress?.call(entries.length, entries.length, '');

      return PackImport(
        kind: PackKind.launcher,
        name:
            manifest['name'] as String? ??
            p.basenameWithoutExtension(pack.path),
        gameVersion: manifest['versionId'] as String? ?? '',
        loader: LoaderKind.values.firstWhere(
          (kind) => kind.name == manifest['loader'],
          orElse: () => LoaderKind.vanilla,
        ),
        loaderVersion: manifest['loaderVersion'] as String?,
        written: written,
        failed: failed,
      );
    } finally {
      await reader.close();
    }
  }

  Future<PackImport> _importMrpack(
    MrpackIndex index,
    File pack,
    Directory gameDir,
    void Function(int, int, String)? onProgress,
  ) async {
    final importer = MrpackImporter(client: _client);
    try {
      final result = await importer.import(
        pack,
        gameDir: gameDir,
        onProgress: onProgress,
      );
      return PackImport(
        kind: PackKind.mrpack,
        name: index.name,
        gameVersion: index.minecraft,
        loader: index.loader,
        loaderVersion: index.loaderVersion,
        written: [...result.installed, ...result.skipped],
        failed: result.failed,
      );
    } finally {
      importer.close();
    }
  }

  static String? _safeJoin(Directory root, String relative) {
    if (relative.isEmpty) return null;
    final normalised = p.normalize(relative);
    if (p.isAbsolute(normalised) || normalised.startsWith('..')) return null;
    final target = p.normalize(p.join(root.path, normalised));
    return p.isWithin(root.path, target) ? target : null;
  }

  void close() => _client.close(force: true);
}
