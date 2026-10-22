import 'dart:io';

/// The install log: what the launcher did, in order.
///
/// The download panel can only show the *current* phase - one line that is
/// replaced as the install moves on - so a resumed install looked like nothing
/// happening at all: the phase label changed twice and the panel disappeared. A
/// log answers the questions the panel cannot ("did it start?", "where did it
/// stop?", "what failed?") and, because it is also written to disk, it survives
/// the restart that an interrupted install implies.
///
/// Technical, unlocalized lines on purpose: this is a log, not UI text, and it is
/// read in a monospace console next to the game's own output.
class InstallLog {
  InstallLog({this.file, this.capacity = 400});

  /// Where the lines are appended. `null` keeps the log in memory only (tests).
  final File? file;

  /// A moving window: a long modpack install emits thousands of progress lines and
  /// the interesting ones are always the last few.
  final int capacity;

  final List<String> _lines = [];

  List<String> get lines => List.unmodifiable(_lines);

  bool get isEmpty => _lines.isEmpty;

  /// Appends one line, with a wall-clock timestamp.
  ///
  /// The disk write is best effort: a full or read-only data directory must not
  /// fail an install, and the in-memory copy is what the panel reads.
  void add(String message, {DateTime? at}) {
    final stamp = (at ?? DateTime.now()).toIso8601String().substring(11, 19);
    final line = '$stamp  $message';
    _lines.add(line);
    if (_lines.length > capacity) {
      _lines.removeRange(0, _lines.length - capacity);
    }

    final file = this.file;
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('$line\n', mode: FileMode.append, flush: false);
    } on FileSystemException {
      // See above.
    }
  }

  void clear() => _lines.clear();

  /// The tail of the log as it was left on disk, oldest first.
  ///
  /// Read once when a page opens: the point is to explain an install that is no
  /// longer running, which the in-memory ring cannot do after a restart.
  static List<String> readTail(File file, {int max = 200}) {
    try {
      if (!file.existsSync()) return const [];
      final lines = file.readAsLinesSync();
      return lines.length <= max ? lines : lines.sublist(lines.length - max);
    } on FileSystemException {
      return const [];
    }
  }

  /// One line per install phase, in the shape a log reader expects.
  static String describePhase(
    String phase, {
    String? detail,
    int? step,
    int? steps,
    int? bytesDone,
    int? bytesTotal,
  }) {
    final parts = <String>[
      phase,
      if (step != null && steps != null) '[$step/$steps]',
      if (detail != null && detail.isNotEmpty) detail,
      if (bytesDone != null && bytesTotal != null && bytesTotal > 0)
        '${_mb(bytesDone)}/${_mb(bytesTotal)} MB',
    ];
    return parts.join(' ');
  }

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
}
