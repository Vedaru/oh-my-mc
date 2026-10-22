import 'dart:io';

import 'package:path/path.dart' as p;

/// One line of a log file, with the channel it came from.
///
/// The file cannot store a channel, so the launcher writes stderr lines with a
/// leading `! ` (see `ProcessLaunchHandle`). Parsing that back is what lets the
/// Logs page keep its "errors only" filter for a session that ended yesterday.
class LogEntry {
  const LogEntry(this.text, {this.isStderr = false});

  final String text;
  final bool isStderr;
}

/// A log file on disk: one per launch, plus the install log.
class LogFile {
  const LogFile({
    required this.file,
    required this.label,
    required this.modified,
    required this.isInstall,
  });

  final File file;

  /// What the list shows: the version and time for a launch, `install` for the
  /// shared install log (there is only ever one of those).
  final String label;

  final DateTime modified;

  /// The install log is shared by every install; launch logs are per session.
  final bool isInstall;

  int get sizeBytes => file.existsSync() ? file.lengthSync() : 0;
}

/// Every log the launcher has written, newest first.
///
/// Session logs are `launch-<timestamp>-<version>.log`; the install log is
/// `install.log` and is appended across runs, so it is one entry, not one per
/// install.
Future<List<LogFile>> listLogFiles(
  Directory dir, {
  String installFileName = 'install.log',
}) async {
  if (!await dir.exists()) return const [];

  final files = <LogFile>[];
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    if (!name.endsWith('.log')) continue;

    final isInstall = name == installFileName;
    final stat = await entity.stat();
    files.add(
      LogFile(
        file: entity,
        isInstall: isInstall,
        modified: stat.modified,
        label: isInstall ? 'install' : _launchLabel(name),
      ),
    );
  }

  files.sort((a, b) => b.modified.compareTo(a.modified));
  return files;
}

/// `launch-2026-10-22T23-58-14-26.3.log` → `26.3 · 23:58`
///
/// The timestamp is written with `:` replaced by `-` (Windows forbids `:` in file
/// names), so this reads the version out of the tail rather than parsing a date:
/// a version id can contain dashes, a timestamp cannot.
String _launchLabel(String name) {
  var rest = name;
  if (rest.startsWith('launch-')) rest = rest.substring('launch-'.length);
  if (rest.endsWith('.log')) rest = rest.substring(0, rest.length - 4);

  // `2026-10-22T23-58-14-<version>` splits on '-' into
  // [2026, 10, 22T23, 58, 14, <version...>]: the hour hides inside the third part
  // because the date and time are joined by 'T'.
  final parts = rest.split('-');
  if (parts.length >= 6) {
    final dayAndHour = parts[2].split('T');
    final hour = dayAndHour.length > 1 ? dayAndHour[1] : '';
    final time = hour.isEmpty ? '' : '$hour:${parts[3]}';
    final version = parts.sublist(5).join('-');
    if (version.isEmpty) return time;
    return time.isEmpty ? version : '$version · $time';
  }
  return rest;
}

/// The last [max] lines of [file], oldest first.
///
/// A tail rather than the whole file: a modded session writes hundreds of
/// thousands of lines, and nothing in the UI needs the first one.
Future<List<LogEntry>> readLogTail(File file, {int max = 4000}) async {
  if (!await file.exists()) return const [];
  try {
    final lines = await file.readAsLines();
    final tail = lines.length <= max
        ? lines
        : lines.sublist(lines.length - max);
    return [
      for (final line in tail)
        if (line.startsWith('! '))
          LogEntry(line.substring(2), isStderr: true)
        else
          LogEntry(line),
    ];
  } on FileSystemException {
    return const [];
  }
}
