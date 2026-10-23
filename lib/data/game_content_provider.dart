import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:typed_data';

import '../core/game/content.dart';
import '../core/game/content_icons.dart';

/// Where a [GameContent] comes from.
///
/// A provider so a widget test can answer without touching a real directory: the
/// content pages read the disk, and real file I/O does not complete inside
/// `pumpAndSettle`'s fake clock. The disk behaviour itself is pinned by
/// `test/core/game/content_test.dart` against a real temp tree.
final gameContentProvider = Provider<GameContent Function(String root)>(
  (ref) => GameContent.new,
);

/// Where a pack or world's icon comes from, keyed by path.
///
/// `autoDispose` because the answer is only needed while the row is on screen: a list
/// of 200 mods should not pin 200 icon byte arrays in memory after it is closed.
final contentIconProvider = FutureProvider.autoDispose
    .family<Uint8List?, ({String path, bool isDirectory})>(
      (ref, key) =>
          const ContentIcons().forEntry(key.path, isDirectory: key.isDirectory),
    );
