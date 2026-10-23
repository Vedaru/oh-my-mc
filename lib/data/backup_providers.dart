import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/game/world_backup.dart';

/// Where a world backup is made and restored from.
///
/// A provider so a test can answer without zipping a real world: the service writes and
/// reads files, and a widget test that touches the disk is a widget test that hangs.
final worldBackupServiceProvider = Provider<WorldBackupService>(
  (ref) => const WorldBackupService(),
);

/// The icon/theme-agnostic decision of which directory backups live in: beside `saves/`,
/// never inside it, so the game never sees a stray archive where it expects a world.
String backupsDirFor(String gameRoot) => '$gameRoot/backups';
