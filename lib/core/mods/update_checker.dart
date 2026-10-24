import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'modrinth.dart';
import 'mod_scanner.dart';

/// One installed file that has a newer version on Modrinth.
///
/// A *file*, not a mod: the launcher knows a path and the sha1 of its bytes, and the same
/// lookup answers for a jar in `mods/`, a zip in `resourcepacks/` and a zip in
/// `shaderpacks/`. Naming this after mods is what made pack updates look like a separate
/// feature nobody had time for.
class FileUpdate {
  const FileUpdate({
    required this.path,
    required this.name,
    required this.installed,
    required this.latest,
  });

  /// Absolute path of the installed file.
  final String path;

  /// What to call it in a row: the mod's name, or the file name for a pack.
  final String name;

  /// The version Modrinth says the installed file belongs to.
  final ModrinthVersion installed;

  /// The newest version for this game version (and loader, for mods).
  final ModrinthVersion latest;

  String get from => installed.versionNumber;
  String get to => latest.versionNumber;
}

/// A file to check, as the caller knows it.
typedef UpdateCandidate = ({String path, String name});

/// Asks Modrinth whether the files in a folder are current.
///
/// `FileUpdateChecker`, not `UpdateChecker`: the launcher's own update check owns that
/// name (`core/update/update_check.dart`), and two different things called one name in
/// one tree is how the wrong one gets imported.
///
/// The launcher knows a file's *path*, not its Modrinth identity. The identity comes from
/// its sha1 - `version_file/{hash}` answers "which version of which project is this",
/// which is the one lookup that works for a jar the user downloaded by hand or copied in
/// from an old setup.
///
/// Updating one file does not move its dependencies: Modrinth's dependency graph is
/// advisory, and silently installing libraries the user did not choose is what makes a
/// list feel out of control. The row says "可更新", the user decides.
class FileUpdateChecker {
  const FileUpdateChecker(this.client, {this.hash});

  final ModrinthClient client;

  /// How a file is identified. Injectable so a test does not have to hash a real file
  /// (and so a future "hash once, cache in the instance" stays a one-line change).
  final Future<String?> Function(File file)? hash;

  /// Checks [files]. Unreadable files, files Modrinth has never seen and versions with no
  /// matching release are skipped - a list of updates that cannot be installed is worse
  /// than a shorter list.
  ///
  /// [projectType] is Modrinth's `mod` / `resourcepack` / `shader`: it decides whether a
  /// loader filter applies (only mods have one) and which catalogue the project lives in.
  Future<List<FileUpdate>> checkFiles(
    Iterable<UpdateCandidate> files, {
    required String gameVersion,
    String? loader,
    String projectType = 'mod',
    void Function(int done, int total)? onProgress,
  }) async {
    final candidates = files.toList();
    final updates = <FileUpdate>[];
    var done = 0;
    for (final file in candidates) {
      done++;
      onProgress?.call(done, candidates.length);
      try {
        final digest = await (hash ?? _sha1)(File(file.path));
        if (digest == null) continue;
        final installed = await client.versionForFile(digest);
        final latest = await client.versionFor(
          installed.projectId,
          gameVersion: gameVersion,
          loader: loader,
          projectType: projectType,
        );
        if (latest.id != installed.id) {
          updates.add(
            FileUpdate(
              path: file.path,
              name: file.name,
              installed: installed,
              latest: latest,
            ),
          );
        }
      } on Object {
        // No match, no network, corrupt file: this one simply has no update to offer.
        continue;
      }
    }
    return updates;
  }

  /// The mods-folder spelling of [checkFiles]: a jar's row name is the mod's own name.
  Future<List<FileUpdate>> checkMods(
    List<ModEntry> mods, {
    required String gameVersion,
    String? loader,
    void Function(int done, int total)? onProgress,
  }) => checkFiles(
    [
      for (final mod in mods)
        (path: mod.path, name: mod.name ?? p.basename(mod.path)),
    ],
    gameVersion: gameVersion,
    loader: loader,
    onProgress: onProgress,
  );

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
