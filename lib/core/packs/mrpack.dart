import 'dart:convert';
import 'dart:io';

import '../mods/zip_entry_reader.dart';

import '../instance/instance.dart';

/// A file a modpack wants present, at a path relative to the game directory.
class MrpackFile {
  const MrpackFile({
    required this.path,
    required this.downloads,
    this.fileSize = 0,
    this.sha1,
    this.clientUnsupported = false,
    this.serverUnsupported = false,
  });

  factory MrpackFile.fromJson(Map<String, dynamic> json) {
    final env = json['env'];
    final hashes = json['hashes'];
    return MrpackFile(
      path: json['path'] as String? ?? '',
      downloads: [
        for (final url in (json['downloads'] as List? ?? const []))
          if (url is String) url,
      ],
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      sha1: hashes is Map ? hashes['sha1'] as String? : null,
      clientUnsupported: env is Map && env['client'] == 'unsupported',
      serverUnsupported: env is Map && env['server'] == 'unsupported',
    );
  }

  /// `mods/sodium.jar`, relative to the game directory.
  final String path;

  /// Mirrors, most preferred first.
  final List<String> downloads;

  final int fileSize;
  final String? sha1;

  /// The pack ships this only for a server: installing it client-side is wrong.
  final bool clientUnsupported;
  final bool serverUnsupported;
}

/// `modrinth.index.json`: the manifest of a `.mrpack`.
///
/// A `.mrpack` is a zip holding this file, an `overrides/` folder applied to both
/// sides, and a `client-overrides/` folder applied only to the client. Nothing
/// else in it is authoritative - the jars are downloaded by URL, not shipped.
class MrpackIndex {
  const MrpackIndex({
    required this.name,
    required this.minecraft,
    required this.files,
    this.versionId,
    this.loaderName,
    this.loaderVersion,
  });

  final String name;

  /// MC version, e.g. `1.20.1`.
  final String minecraft;

  /// Modrinth's own version label for the pack, shown to the user.
  final String? versionId;

  /// `fabric-loader`, `quilt-loader`, `forge`, `neoforge`.
  final String? loaderName;
  final String? loaderVersion;

  final List<MrpackFile> files;

  /// Reads the manifest out of a `.mrpack` without downloading anything.
  ///
  /// The manifest is what names the Minecraft version and the loader, so an installer
  /// has to read it *before* it decides what to install - and the same read is what makes
  /// an import repeatable.
  static Future<MrpackIndex> read(File pack) async {
    final reader = await ZipEntryReader.open(pack);
    try {
      final manifest = await reader.readFirst(const ['modrinth.index.json']);
      if (manifest == null) {
        throw const FormatException(
          'not a Modrinth pack: no modrinth.index.json',
        );
      }
      return MrpackIndex.parse(manifest);
    } finally {
      await reader.close();
    }
  }

  /// Throws [FormatException] for anything that is not a modrinth index.
  factory MrpackIndex.parse(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('modrinth.index.json is not an object');
    }
    // formatVersion 1 is the only one that exists; a future one may change what
    // `files[*].path` means, so it is refused rather than misread.
    final format = decoded['formatVersion'];
    if (format != 1) {
      throw FormatException('unsupported mrpack formatVersion $format');
    }
    final dependencies = decoded['dependencies'];
    if (dependencies is! Map) {
      throw const FormatException('mrpack has no dependencies');
    }
    final minecraft = dependencies['minecraft'];
    if (minecraft is! String || minecraft.isEmpty) {
      throw const FormatException('mrpack does not name a Minecraft version');
    }

    final loaderName = _loaderNameOf(dependencies);
    return MrpackIndex(
      name: decoded['name'] as String? ?? 'imported pack',
      versionId: decoded['versionId'] as String?,
      minecraft: minecraft,
      loaderName: loaderName,
      loaderVersion: loaderName == null
          ? null
          : dependencies[loaderName] as String?,
      files: [
        for (final file in (decoded['files'] as List? ?? const []))
          if (file is Map<String, dynamic>) MrpackFile.fromJson(file),
      ],
    );
  }

  static String? _loaderNameOf(Map dependencies) {
    for (final key in const [
      'fabric-loader',
      'quilt-loader',
      'neoforge',
      'forge',
    ]) {
      if (dependencies[key] is String) return key;
    }
    return null;
  }

  /// The launcher's notion of the loader, for the instance it creates.
  LoaderKind get loader => switch (loaderName) {
    'fabric-loader' => LoaderKind.fabric,
    'quilt-loader' => LoaderKind.quilt,
    'forge' => LoaderKind.forge,
    'neoforge' => LoaderKind.neoforge,
    _ => LoaderKind.vanilla,
  };

  /// Files a client installs: everything except server-only entries.
  Iterable<MrpackFile> get clientFiles => files.where(
    (file) => !file.clientUnsupported && file.downloads.isNotEmpty,
  );
}
