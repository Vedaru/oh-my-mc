import 'dart:io';

import 'package:path/path.dart' as p;

/// Removes one installed version from `versions/`.
///
/// What "uninstall" means and does not mean:
///
/// * it deletes the version's own directory - its JSON, client jar, natives and the
///   loader profile that lives beside them;
/// * it **never** touches `libraries/` or `assets/`. Those are shared by every version;
///   deleting them to reclaim a few hundred megabytes would break every other version
///   the user still has, which is the opposite of an uninstall;
/// * it does not delete instances. An instance that pointed at this version is left
///   alone and simply reports a missing version, which is the state the launch page
///   already knows how to explain and repair.
class VersionRemover {
  const VersionRemover();

  /// Deletes `versions/<versionId>`, returning true when something was removed.
  Future<bool> remove(String versionId, {required String versionsDir}) async {
    final id = versionId.trim();
    // A version id is a directory name. Anything with a separator in it is a path
    // traversal wearing a version's clothes, and `..` would delete the game root.
    if (id.isEmpty ||
        id == '.' ||
        id == '..' ||
        id.contains('/') ||
        id.contains('\\') ||
        id.contains(p.separator)) {
      throw ArgumentError('not a version id: $versionId');
    }

    final directory = Directory(p.join(versionsDir, id));
    if (!await directory.exists()) return false;
    await directory.delete(recursive: true);
    return true;
  }

  /// Whether [versionId] has a directory on disk, installed or not.
  Future<bool> exists(String versionId, {required String versionsDir}) =>
      Directory(p.join(versionsDir, versionId)).exists();
}
