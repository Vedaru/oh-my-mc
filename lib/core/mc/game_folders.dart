import 'dart:io';

/// The per-version content folders PCL surfaces in 版本设置.
///
/// They are just directories under the game root, but they are the four answers to
/// "where do I put my mods / packs", which is the question a new user actually has.
/// Naming them in one place keeps the names out of three screens.
enum GameFolderKind {
  mods('mods'),
  resourcePacks('resourcepacks'),
  shaderPacks('shaderpacks'),
  saves('saves');

  const GameFolderKind(this.directoryName);

  /// The on-disk name. Never localized: the game reads these paths, not the UI.
  final String directoryName;
}

/// One folder plus what is in it.
class GameFolder {
  const GameFolder({
    required this.kind,
    required this.path,
    required this.entries,
  });

  final GameFolderKind kind;
  final String path;

  /// How many things are in it, counted by the rule in [scanGameFolders].
  final int entries;
}

/// Counts what each folder *contains that the game would load*.
///
/// Not a plain file count: `mods/` holds `.jar` and `.jar.disabled` (a disabled mod
/// is still a mod the user recognizes), resource and shader packs are zips or
/// directories, and a save is a directory. Counting everything would make an empty
/// pack folder read as "3 entries" because of a thumbnail or a readme.
Future<List<GameFolder>> scanGameFolders(String gameRoot) async {
  final result = <GameFolder>[];
  for (final kind in GameFolderKind.values) {
    final dir = Directory('$gameRoot/${kind.directoryName}');
    var count = 0;
    if (await dir.exists()) {
      await for (final entry in dir.list(followLinks: false)) {
        final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
        count += _counts(kind, entry, name) ? 1 : 0;
      }
    }
    result.add(GameFolder(kind: kind, path: dir.path, entries: count));
  }
  return result;
}

bool _counts(GameFolderKind kind, FileSystemEntity entry, String name) {
  final lower = name.toLowerCase();
  switch (kind) {
    case GameFolderKind.mods:
      // A disabled mod is renamed with a suffix by every launcher, including this
      // one; it is still one of the user's mods.
      return lower.endsWith('.jar') || lower.endsWith('.jar.disabled');
    case GameFolderKind.resourcePacks:
    case GameFolderKind.shaderPacks:
      return entry is Directory || lower.endsWith('.zip');
    case GameFolderKind.saves:
      return entry is Directory;
  }
}
