import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/game/content.dart';

/// Where a [GameContent] comes from.
///
/// A provider so a widget test can answer without touching a real directory: the
/// content pages read the disk, and real file I/O does not complete inside
/// `pumpAndSettle`'s fake clock. The disk behaviour itself is pinned by
/// `test/core/game/content_test.dart` against a real temp tree.
final gameContentProvider = Provider<GameContent Function(String root)>(
  (ref) => GameContent.new,
);
