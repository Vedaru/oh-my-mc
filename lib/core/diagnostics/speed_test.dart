import 'dart:async';
import 'dart:io';

/// One mirror's measurement.
class SpeedSample {
  const SpeedSample({
    required this.name,
    required this.url,
    this.bytes = 0,
    this.elapsed = Duration.zero,
    this.error,
  });

  final String name;
  final String url;
  final int bytes;
  final Duration elapsed;
  final String? error;

  bool get ok => error == null && bytes > 0;

  /// Bytes per second, or 0 when the sample failed.
  double get bytesPerSecond => elapsed.inMicroseconds == 0
      ? 0
      : bytes * Duration.microsecondsPerSecond / elapsed.inMicroseconds;

  String get label {
    if (!ok) return error ?? 'failed';
    final mbps = bytesPerSecond / (1024 * 1024);
    return '${mbps.toStringAsFixed(1)} MB/s';
  }
}

/// A mirror worth measuring: the hosts a launch actually downloads from.
class Mirror {
  const Mirror(this.name, this.url);

  final String name;
  final String url;

  /// The default set: one file each from the three CDNs an install touches.
  ///
  /// Small on purpose - a speed test that takes a minute is a speed test nobody
  /// runs. [maxBytes] caps it anyway.
  static const defaults = [
    Mirror(
      'Mojang',
      'https://piston-data.mojang.com/v1/objects/'
          '5b8b41b5d5b1a2a5e3a0d8b1f6f2c0a6e1d3f4a7/client.jar',
    ),
    Mirror(
      'Modrinth',
      'https://cdn.modrinth.com/data/AANobbMI/versions/'
          'mc1.20.1-0.5.13-fabric/sodium-fabric-0.5.13%2Bmc1.20.1.jar',
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
  }) : _client = client ?? HttpClient();

  final HttpClient _client;

  /// Stop after this much: enough to average out TCP ramp-up, small enough to be
  /// polite to the CDN.
  final int maxBytes;
  final Duration timeout;

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

  Future<SpeedSample> measure(Mirror mirror) async {
    final watch = Stopwatch()..start();
    var received = 0;
    try {
      final request = await _client
          .getUrl(Uri.parse(mirror.url))
          .timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return SpeedSample(
          name: mirror.name,
          url: mirror.url,
          error: 'HTTP ${response.statusCode}',
          elapsed: watch.elapsed,
        );
      }

      // Read until the cap, then cancel the subscription: that is what actually
      // stops the transfer (draining a 100 MB file to find out how fast the first
      // 2 MB arrived would be absurd). Chunks arrive at socket granularity, so
      // `received` can overshoot the cap by one chunk - reported as measured,
      // because those bytes were transferred.
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
    } on Object catch (e) {
      return SpeedSample(
        name: mirror.name,
        url: mirror.url,
        bytes: received,
        elapsed: watch.elapsed,
        error: _describe(e),
      );
    } finally {
      watch.stop();
    }
    return SpeedSample(
      name: mirror.name,
      url: mirror.url,
      bytes: received,
      elapsed: watch.elapsed,
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
