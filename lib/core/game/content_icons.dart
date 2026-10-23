import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../mods/zip_entry_reader.dart';

/// The little image a pack or a save carries, so a list of them is not a list of
/// identical rows.
///
/// Minecraft's own formats put it in a known place - `pack.png` at the root of a
/// resource pack or shader pack, `icon.png` inside a world - and both are small (64×64
/// in practice). A launcher that shows them looks like it knows what is installed; a
/// launcher that does not makes the user read every filename.
///
/// Nothing here throws. A corrupt archive, a missing icon or a 40 MB "icon" is a
/// reason to fall back to the kind's icon, not a reason to fail a list.
class ContentIcons {
  const ContentIcons({this.maxBytes = 256 * 1024});

  /// An icon larger than this is not an icon; refuse rather than decode it.
  final int maxBytes;

  static const packEntry = 'pack.png';
  static const worldEntry = 'icon.png';

  /// The icon for [path], or null when there is none worth showing.
  Future<Uint8List?> forEntry(String path, {required bool isDirectory}) async {
    try {
      final entity = isDirectory ? Directory(path) : File(path);
      if (isDirectory) {
        final icon = File(p.join(entity.path, worldEntry));
        if (!await icon.exists()) return null;
        final length = await icon.length();
        if (length == 0 || length > maxBytes) return null;
        return await icon.readAsBytes();
      }

      final file = entity as File;
      if (!await file.exists()) return null;
      if (await file.length() > 512 * 1024 * 1024) return null;
      final reader = await ZipEntryReader.open(file);
      try {
        final bytes = await reader.read(packEntry);
        if (bytes == null || bytes.isEmpty || bytes.length > maxBytes) {
          return null;
        }
        return bytes;
      } finally {
        await reader.close();
      }
    } on Object {
      return null;
    }
  }
}
