import 'dart:io';

import 'package:crypto/crypto.dart';

import 'modrinth.dart';
import 'mod_scanner.dart';

/// One installed mod that has a newer version on Modrinth.
class ModUpdate {
  const ModUpdate({
    required this.mod,
    required this.installed,
    required this.latest,
  });

  final ModEntry mod;

  /// The version Modrinth says the installed file belongs to.
  final ModrinthVersion installed;

  /// The newest version for this game version and loader.
  final ModrinthVersion latest;

  String get from => installed.versionNumber;
  String get to => latest.versionNumber;
}

/// Asks Modrinth whether the mods in a folder are current.
///
/// The launcher knows a jar's *path*, not its Modrinth identity. The identity comes from
/// the file's sha1 - `version_file/{hash}` answers "which version of which project is
/// this", which is the one lookup that works for a jar the user downloaded by hand or
/// copied in from an old setup.
///
/// Update a mod and its dependencies do not move: Modrinth's dependency graph is
/// advisory, and silently installing libraries the user did not choose is what makes a
/// mod list feel out of control. The row says "可更新", the user decides.
class ModUpdateChecker {
  const ModUpdateChecker(this.client, {this.hash});

  final ModrinthClient client;

  /// How a jar is identified. Injectable so a test does not have to hash a real file
  /// (and so a future "hash once, cache in the instance" stays a one-line change).
  final Future<String?> Function(File file)? hash;

  /// Checks every mod in [mods]. Unreadable files, jars Modrinth has never seen and
  /// versions with no matching release are skipped - a list of updates that cannot be
  /// installed is worse than a shorter list.
  Future<List<ModUpdate>> check(
    List<ModEntry> mods, {
    required String gameVersion,
    String? loader,
    void Function(int done, int total)? onProgress,
  }) async {
    final updates = <ModUpdate>[];
    var done = 0;
    for (final mod in mods) {
      done++;
      onProgress?.call(done, mods.length);
      try {
        final digest = await (hash ?? _sha1)(File(mod.path));
        if (digest == null) continue;
        final installed = await client.versionForFile(digest);
        final latest = await client.versionFor(
          installed.projectId,
          gameVersion: gameVersion,
          loader: loader,
        );
        if (latest.id != installed.id) {
          updates.add(
            ModUpdate(mod: mod, installed: installed, latest: latest),
          );
        }
      } on Object {
        // No match, no network, corrupt jar: the mod simply has no update to offer.
        continue;
      }
    }
    return updates;
  }

  /// The sha1 of a file, or null when it cannot be read.
  Future<String?> _sha1(File file) async {
    try {
      final digest = await sha1.bind(file.openRead()).first;
      return digest.toString();
    } on Object {
      return null;
    }
  }
}
