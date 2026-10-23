import 'dart:io';

import 'package:path/path.dart' as p;

import 'nbt.dart';
import 'options_txt.dart';

/// The kinds of content 版本设置 manages.
enum ContentKind {
  resourcePacks('resourcepacks'),
  shaderPacks('shaderpacks'),
  saves('saves'),
  servers('servers.dat'),

  /// Data packs live *inside a world* (`saves/<world>/datapacks`), which is why this
  /// kind is read with a world directory as the root rather than the game root.
  datapacks('datapacks');

  const ContentKind(this.path);

  /// Directory (or file, for servers) under the game root. Never localised: the
  /// game reads these paths.
  final String path;
}

/// One entry in a content list.
class ContentEntry {
  const ContentEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.sizeBytes = 0,
    this.enabled = true,
    this.detail,
    this.modified,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final int sizeBytes;

  /// Whether the game will load it. For resource packs this is read from
  /// `options.txt`; for a save or a server the notion does not apply and is always
  /// true.
  final bool enabled;

  /// A second line worth showing: a server address, a world's last-played time.
  final String? detail;

  final DateTime? modified;
}

/// Reads and edits the four content kinds of one game directory.
///
/// The rule that shapes all of it: **the game owns these files**. `options.txt` is
/// rewritten by the game on exit and `servers.dat` is NBT that must round-trip
/// byte-compatibly enough for the game to open it, so everything here reads the
/// current state first and writes back only the field it was asked to change.
class GameContent {
  GameContent(this.gameRoot);

  final String gameRoot;

  /// A server from `servers.dat`.
  static const serverNameKey = 'name';
  static const serverIpKey = 'ip';

  Future<List<ContentEntry>> list(ContentKind kind) async {
    switch (kind) {
      case ContentKind.resourcePacks:
        return _listPacks(kind, await _readOptions());
      case ContentKind.shaderPacks:
      case ContentKind.datapacks:
        return _listPacks(kind, await _readOptions());
      case ContentKind.saves:
        return _listSaves();
      case ContentKind.servers:
        return _listServers();
    }
  }

  Future<OptionsTxt> _readOptions() =>
      OptionsTxt.read(File(p.join(gameRoot, 'options.txt')));

  Future<List<ContentEntry>> _listPacks(
    ContentKind kind,
    OptionsTxt options,
  ) async {
    final dir = Directory(p.join(gameRoot, kind.path));
    if (!await dir.exists()) return const [];

    final enabledIds = kind == ContentKind.resourcePacks
        // Only resource packs have an enabled state the launcher can express: Iris
        // stores its active shader in its own config, and pretending otherwise
        // would show a toggle that lies.
        ? options.resourcePacks.toSet()
        : const <String>{};

    final entries = <ContentEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      final name = p.basename(entity.path);
      final lower = name.toLowerCase();
      final isDir = entity is Directory;
      if (!isDir && !lower.endsWith('.zip')) continue;

      // Branching on the entity type here rather than on a bool keeps the sizes
      // cast-free: the analyzer promotes `entity` inside each branch.
      final int sizeBytes;
      if (entity is Directory) {
        sizeBytes = await _directorySize(entity);
      } else if (entity is File) {
        sizeBytes = await entity.length();
      } else {
        continue;
      }

      entries.add(
        ContentEntry(
          name: name,
          path: entity.path,
          isDirectory: isDir,
          sizeBytes: sizeBytes,
          enabled: kind != ContentKind.resourcePacks
              ? true
              : enabledIds.contains(packIdFor(name)),
          modified: await entity.stat().then((s) => s.modified),
        ),
      );
    }
    entries.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return entries;
  }

  Future<List<ContentEntry>> _listSaves() async {
    final dir = Directory(p.join(gameRoot, 'saves'));
    if (!await dir.exists()) return const [];

    final entries = <ContentEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final stat = await entity.stat();
      entries.add(
        ContentEntry(
          name: p.basename(entity.path),
          path: entity.path,
          isDirectory: true,
          sizeBytes: await _directorySize(entity),
          modified: stat.modified,
          // The folder name is the world's display name for every world the game
          // created; only a hand-renamed folder differs, and then it is still the
          // name the user sees in this list.
          detail: _relative(stat.modified),
        ),
      );
    }
    // Most recently played first: the world someone wants is almost always the one
    // they played last.
    entries.sort(
      (a, b) =>
          (b.modified ?? DateTime(0)).compareTo(a.modified ?? DateTime(0)),
    );
    return entries;
  }

  Future<List<ContentEntry>> _listServers() async {
    final file = File(p.join(gameRoot, 'servers.dat'));
    if (!await file.exists()) return const [];
    try {
      final root = readNbt(await file.readAsBytes());
      final list = root.values['servers'];
      if (list is! NbtList) return const [];
      return [
        for (final item in list.items)
          if (item is NbtCompound && item.string(serverIpKey) != null)
            ContentEntry(
              name: item.string(serverNameKey) ?? item.string(serverIpKey)!,
              path: item.string(serverIpKey)!,
              isDirectory: false,
              detail: item.string(serverIpKey),
            ),
      ];
    } on Object {
      // A corrupted servers.dat is not worth failing the screen over: an empty list
      // plus the file still on disk beats an error page.
      return const [];
    }
  }

  /// Flips a resource pack's enabled state in `options.txt`.
  ///
  /// Returns the pack list as written, so the caller can show it without re-reading.
  Future<List<String>> setResourcePackEnabled(String name, bool enabled) async {
    final file = File(p.join(gameRoot, 'options.txt'));
    final options = await _readOptions();
    final id = packIdFor(name);
    final packs = [...options.resourcePacks];
    if (enabled) {
      if (!packs.contains(id)) packs.add(id);
    } else {
      packs.remove(id);
    }
    options.setResourcePacks(packs);
    await file.writeAsString(options.text, flush: true);
    return packs;
  }

  /// Deletes one entry, file or directory.
  Future<void> delete(ContentKind kind, String path) async {
    if (kind == ContentKind.servers) {
      await _deleteServer(path);
      return;
    }
    final entity = FileSystemEntity.typeSync(path);
    if (entity == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else if (entity == FileSystemEntityType.file) {
      await File(path).delete();
    }
  }

  Future<void> _deleteServer(String ip) async {
    final file = File(p.join(gameRoot, 'servers.dat'));
    if (!await file.exists()) return;
    final root = readNbt(await file.readAsBytes());
    final list = root.values['servers'];
    if (list is! NbtList) return;
    list.items.removeWhere(
      (item) => item is NbtCompound && item.string(serverIpKey) == ip,
    );
    await file.writeAsBytes(writeNbt(root), flush: true);
  }

  /// Adds a server to `servers.dat`, creating the file when needed.
  ///
  /// The game re-writes this file on exit with its own field order; this writes the
  /// fields it reads and nothing else, so the two coexist.
  Future<void> addServer({required String name, required String ip}) async {
    final file = File(p.join(gameRoot, 'servers.dat'));
    var root = await file.exists()
        ? readNbt(await file.readAsBytes())
        : NbtCompound();
    final existing = root.values['servers'];
    final list = existing is NbtList
        ? existing
        : NbtList(NbtTagId.compound, <NbtTag>[]);
    list.items.add(
      NbtCompound({
        'name': NbtString(name),
        'ip': NbtString(ip),
        'icon': NbtString(''),
        'acceptTextures': NbtByte(1),
      }),
    );
    root = NbtCompound(root.values)..values['servers'] = list;
    await file.writeAsBytes(writeNbt(root), flush: true);
  }

  static Future<int> _directorySize(Directory dir) async {
    var total = 0;
    try {
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) total += await entity.length();
      }
    } on FileSystemException {
      // A world with an unreadable file still gets a size for the rest.
    }
    return total;
  }

  static String _relative(DateTime time) {
    final delta = DateTime.now().difference(time);
    if (delta.inMinutes < 1) return 'just now';
    if (delta.inHours < 1) return '${delta.inMinutes} min ago';
    if (delta.inDays < 1) return '${delta.inHours} h ago';
    if (delta.inDays < 30) return '${delta.inDays} d ago';
    return '${delta.inDays ~/ 30} mo ago';
  }
}

/// `1.2 MB` / `340 KB`, for a list row's trailing text.
String formatContentSize(int bytes) {
  if (bytes <= 0) return '0 KB';
  const kb = 1024;
  const mb = 1024 * 1024;
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
  return '$bytes B';
}
