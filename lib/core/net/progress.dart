/// Aggregate download progress, as the animated install UI consumes it.
///
/// Speed and ETA are computed from a short window of samples rather than the
/// whole run, so a slow first file does not make the ETA look wrong for minutes
/// (and so a stalled transfer converges to "unknown" instead of lying).
class DownloadProgress {
  const DownloadProgress({
    required this.filesDone,
    required this.filesTotal,
    required this.bytesDone,
    required this.bytesTotal,
    this.bytesPerSecond,
    this.currentFile,
  });

  static const idle = DownloadProgress(
    filesDone: 0,
    filesTotal: 0,
    bytesDone: 0,
    bytesTotal: 0,
  );

  final int filesDone;
  final int filesTotal;
  final int bytesDone;
  final int bytesTotal;

  /// `null` until enough samples exist to be meaningful.
  final double? bytesPerSecond;

  final String? currentFile;

  double get fraction {
    if (bytesTotal > 0) return (bytesDone / bytesTotal).clamp(0.0, 1.0);
    if (filesTotal > 0) return (filesDone / filesTotal).clamp(0.0, 1.0);
    return 0;
  }

  bool get isComplete => filesTotal > 0 && filesDone >= filesTotal;

  Duration? get eta {
    final speed = bytesPerSecond;
    if (speed == null || speed <= 0 || bytesTotal <= 0) return null;
    final remaining = bytesTotal - bytesDone;
    if (remaining <= 0) return Duration.zero;
    return Duration(milliseconds: (remaining / speed * 1000).round());
  }

  DownloadProgress copyWith({
    int? filesDone,
    int? filesTotal,
    int? bytesDone,
    int? bytesTotal,
    double? bytesPerSecond,
    String? currentFile,
  }) => DownloadProgress(
    filesDone: filesDone ?? this.filesDone,
    filesTotal: filesTotal ?? this.filesTotal,
    bytesDone: bytesDone ?? this.bytesDone,
    bytesTotal: bytesTotal ?? this.bytesTotal,
    bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
    currentFile: currentFile ?? this.currentFile,
  );

  @override
  String toString() =>
      '${(fraction * 100).toStringAsFixed(1)}% '
      '($filesDone/$filesTotal files, $bytesDone/$bytesTotal bytes)';
}

/// Turns raw counters into [DownloadProgress] with a smoothed transfer rate.
///
/// Time is injected so the smoothing is unit-testable without sleeping.
class ProgressTracker {
  ProgressTracker({
    required this.filesTotal,
    required this.bytesTotal,
    this.window = const Duration(seconds: 3),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int filesTotal;
  final int bytesTotal;
  final Duration window;
  final DateTime Function() _clock;

  final List<({DateTime at, int bytes})> _samples = [];
  int _filesDone = 0;
  int _bytesDone = 0;
  String? _currentFile;

  int get filesDone => _filesDone;
  int get bytesDone => _bytesDone;

  void startFile(String name) => _currentFile = name;

  void addBytes(int n) {
    if (n <= 0) return;
    _bytesDone += n;
    _record(_bytesDone);
  }

  void completeFile() {
    _filesDone++;
    _record(_bytesDone);
  }

  void _record(int total) {
    final now = _clock();
    _samples.add((at: now, bytes: total));
    // Keep one sample older than the window so the rate spans the full window.
    final cutoff = now.subtract(window);
    while (_samples.length > 2 && _samples[1].at.isBefore(cutoff)) {
      _samples.removeAt(0);
    }
  }

  /// Bytes/second over the retained window; `null` when it cannot be measured.
  double? get rate {
    if (_samples.length < 2) return null;
    final first = _samples.first;
    final last = _samples.last;
    final elapsed = last.at.difference(first.at);
    if (elapsed <= Duration.zero) return null;
    final delta = last.bytes - first.bytes;
    if (delta < 0) return null;
    return delta / (elapsed.inMicroseconds / 1e6);
  }

  DownloadProgress snapshot() => DownloadProgress(
    filesDone: _filesDone,
    filesTotal: filesTotal,
    bytesDone: _bytesDone,
    bytesTotal: bytesTotal,
    bytesPerSecond: rate,
    currentFile: _currentFile,
  );
}

/// Human-readable byte count, for the UI. Uses 1024-based units like every
/// file manager the user will compare against.
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// Human-readable rate, e.g. `2.4 MB/s`.
String formatRate(double? bytesPerSecond) =>
    bytesPerSecond == null ? '—' : '${formatBytes(bytesPerSecond.round())}/s';

/// Human-readable ETA, e.g. `1m 20s`.
String formatEta(Duration? eta) {
  if (eta == null) return '—';
  final s = eta.inSeconds;
  if (s < 60) return '${s}s';
  final m = s ~/ 60;
  final rest = s % 60;
  if (m < 60) return '${m}m ${rest}s';
  return '${m ~/ 60}h ${m % 60}m';
}
