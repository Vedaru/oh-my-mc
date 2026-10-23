import 'dart:async';
import 'dart:io';

/// One mirror's measurement.
class SpeedSample {
  const SpeedSample({
    required this.name,
    required this.url,
    this.bytes = 0,
    this.elapsed = Duration.zero,
    this.firstByte = Duration.zero,
    this.error,
  });

  final String name;
  final String url;
  final int bytes;
  final Duration elapsed;

  /// Time until the first response headers arrived: the number that explains a slow
  /// install of many small files, which throughput alone does not.
  final Duration firstByte;

  final String? error;

  bool get ok => error == null && bytes > 0;

  /// Bytes per second, or 0 when the sample failed.
  double get bytesPerSecond => elapsed.inMicroseconds == 0
      ? 0
      : bytes * Duration.microsecondsPerSecond / elapsed.inMicroseconds;

  String get label {
    if (!ok) return error ?? 'failed';
    final perSecond = bytesPerSecond;
    // Under 1 MB/s the decimal rounds to "0.0", which reads as "broken". Small
    // numbers are shown in KB/s instead.
    if (perSecond < 1024 * 1024) {
      return '${(perSecond / 1024).round()} KB/s';
    }
    return '${(perSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
}

/// A mirror worth measuring: the hosts a launch actually downloads from.
class Mirror {
  const Mirror(this.name, this.url);

  final String name;
  final String url;

  /// The two sources the launcher can choose between, measured on the *same* file.
  ///
  /// Same file matters: measuring a Mojang library against a Modrinth jar compares
  /// two CDNs and two payloads, and the result says nothing about which source to
  /// prefer. `gson` is a real library every install downloads, so this is the exact
  /// path a user waits on.
  static const defaults = [
    Mirror(
      'Mojang',
      'https://libraries.minecraft.net/com/google/code/gson/gson/2.10.1/'
          'gson-2.10.1.jar',
    ),
    Mirror(
      'BMCLAPI',
      'https://bmclapi2.bangbang93.com/maven/com/google/code/gson/gson/2.10.1/'
          'gson-2.10.1.jar',
    ),
  ];
}

/// Measures throughput against mirrors, one at a time.
///
/// Sequential rather than parallel: parallel samples share the same link and each
/// reports a fraction of the truth, which is how a "speed test" ends up telling a
/// user their 100 Mbit line is 20 Mbit.
class SpeedTest {
  SpeedTest({
    HttpClient? client,
    this.maxBytes = 2 * 1024 * 1024,
    this.timeout = const Duration(seconds: 8),
    this.budget = const Duration(seconds: 5),
  }) : _client = client ?? HttpClient();

  final HttpClient _client;

  /// Stop after this much: enough to average out TCP ramp-up, small enough to be
  /// polite to the CDN.
  final int maxBytes;
  final Duration timeout;

  /// Wall-clock cap for the repeat requests. A speed test that takes a minute is a
  /// speed test nobody runs.
  final Duration budget;

  Future<List<SpeedSample>> run(
    List<Mirror> mirrors, {
    void Function(SpeedSample sample)? onSample,
  }) async {
    final samples = <SpeedSample>[];
    for (final mirror in mirrors) {
      final sample = await measure(mirror);
      samples.add(sample);
      onSample?.call(sample);
    }
    return samples;
  }

  /// Measures `mirror` until [maxBytes] or [budget] is reached.
  ///
  /// Looping rather than one request: the file is small (283 KB), and a single
  /// transfer mostly measures TLS setup - which read as "0.2 MB/s" on a link that is
  /// actually fine. Re-requesting also measures connection reuse, which is what a
  /// real install does (hundreds of libraries, one host).
  Future<SpeedSample> measure(Mirror mirror) async {
    final watch = Stopwatch()..start();
    var received = 0;
    var firstByte = Duration.zero;

    try {
      while (received < maxBytes && watch.elapsed < budget) {
        final request = await _client
            .getUrl(Uri.parse(mirror.url))
            .timeout(timeout);
        final response = await request.close().timeout(timeout);
        if (response.statusCode != HttpStatus.ok) {
          await response.drain<void>();
          return SpeedSample(
            name: mirror.name,
            url: mirror.url,
            bytes: received,
            elapsed: watch.elapsed,
            error: 'HTTP ${response.statusCode}',
          );
        }
        if (firstByte == Duration.zero) firstByte = watch.elapsed;

        // Read until the cap, then cancel the subscription: that is what actually
        // stops the transfer. Chunks arrive at socket granularity, so `received` can
        // overshoot the cap by one chunk - reported as measured, because those bytes
        // were transferred.
        final completer = Completer<void>();
        late StreamSubscription<List<int>> subscription;
        subscription = response.listen(
          (chunk) {
            received += chunk.length;
            if (received >= maxBytes && !completer.isCompleted) {
              subscription.cancel();
              completer.complete();
            }
          },
          onError: (Object error, StackTrace stack) {
            if (!completer.isCompleted) completer.completeError(error, stack);
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
          cancelOnError: true,
        );
        await completer.future.timeout(timeout);
        if (received == 0) break;
      }
    } on Object catch (e) {
      return SpeedSample(
        name: mirror.name,
        url: mirror.url,
        bytes: received,
        elapsed: watch.elapsed,
        firstByte: firstByte,
        error: received > 0 ? null : _describe(e),
      );
    } finally {
      watch.stop();
    }
    return SpeedSample(
      name: mirror.name,
      url: mirror.url,
      bytes: received,
      elapsed: watch.elapsed,
      firstByte: firstByte,
    );
  }

  /// The error, minus the exception class nobody can act on.
  static String _describe(Object error) {
    if (error is SocketException) return error.message;
    if (error is TimeoutException) return 'timed out';
    if (error is HttpException) return error.message;
    return '$error';
  }

  void close() => _client.close(force: true);
}
