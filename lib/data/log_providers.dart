import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logs/log_files.dart';
import 'launch_factory.dart';

/// Where the launcher writes its logs.
Directory logsDirFor(LauncherPaths paths) =>
    Directory('${paths.data.path}/logs');

/// Every session log on disk, newest first.
///
/// Auto-disposed and refreshed on demand: the launcher is the only writer, but a
/// session that ends while this page is open has to appear without a restart.
final logFilesProvider = FutureProvider.autoDispose<List<LogFile>>((ref) async {
  final paths = ref.watch(launcherPathsProvider);
  return listLogFiles(logsDirFor(paths));
});

/// The tail of one log file, newest last.
final logTailProvider = FutureProvider.autoDispose
    .family<List<LogEntry>, String>((ref, path) async {
      return readLogTail(File(path));
    });
