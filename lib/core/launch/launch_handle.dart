import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../mc/arch_compat.dart';
import '../mc/launch_service.dart';

/// Where a line of output came from.
enum LogChannel { stdout, stderr, launcher }

/// The lifecycle of one launch attempt.
///
/// `stopping` is a real state, not a courtesy: there is a grace period between
/// "asked to quit" and "killed", and the UI must not report `exited` while that
/// is happening or the stop button looks like it did nothing.
enum LaunchState { idle, preparing, running, stopping, exited }

/// Why a launch could not be started, as a code the UI localizes.
///
/// Deliberately not a message: `lib/core/` may not import `AppLocalizations`, and
/// a hardcoded English string here would be a string the en/zh parity test
/// cannot see.
enum LaunchFailure { spawnFailed, refused, prepareFailed }

/// Something that happened during a launch.
sealed class LaunchEvent {
  const LaunchEvent();
}

/// One line of output, already split and decoded.
class LaunchLog extends LaunchEvent {
  const LaunchLog(this.text, {this.channel = LogChannel.stdout});

  final String text;
  final LogChannel channel;

  @override
  String toString() => '[${channel.name}] $text';
}

/// The state changed. Emitted for every transition, including the final one.
class LaunchStateChanged extends LaunchEvent {
  const LaunchStateChanged(this.state);

  final LaunchState state;

  @override
  String toString() => 'state -> ${state.name}';
}

/// The launch ended, one way or another.
class LaunchEnded extends LaunchEvent {
  const LaunchEnded({
    required this.exitCode,
    required this.uptime,
    this.failure,
    this.blockers = const [],
  });

  /// Why a refused launch was refused, in the order the checks produced them.
  ///
  /// Carried on the event rather than left in the log because the log is a
  /// string: the UI cannot turn `noRuntime: No Java runtime...` back into a
  /// button that downloads Java. Empty unless [failure] is
  /// [LaunchFailure.refused].
  final List<LaunchBlocker> blockers;

  /// The process exit code, or `null` when no process ever ran.
  final int? exitCode;

  /// How long the game actually ran. Zero for a failed start.
  final Duration uptime;

  /// Set when the launch never produced a process.
  final LaunchFailure? failure;

  bool get succeeded => failure == null && exitCode == 0;

  @override
  String toString() =>
      'ended(exit: $exitCode, uptime: ${uptime.inSeconds}s'
      '${failure == null ? '' : ', failure: ${failure!.name}'})';
}

/// Starts a process.
///
/// Injected so the real handle can be tested against `/bin/sh` without a JVM,
/// and so the play button's tests never need any process at all.
typedef ProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

Future<Process> _defaultStarter(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) => Process.start(executable, arguments, workingDirectory: workingDirectory);

/// A running (or finished) game, observed through one event stream.
///
/// The interface exists so the play button can be driven by a scripted lifecycle
/// while the real implementation is tested separately against real processes.
abstract interface class LaunchHandle {
  LaunchState get state;

  /// Every event from now on. Broadcast, so the console and a state listener can
  /// both attach without stealing from each other.
  Stream<LaunchEvent> get events;

  /// Lines kept for a console that attaches late or is rebuilt. Bounded.
  List<LaunchLog> get recentLog;

  /// The exit code once [state] is [LaunchState.exited].
  int? get exitCode;

  /// Prepares, then spawns. A second call while preparing or running is a no-op
  /// rather than a second game process.
  Future<void> start();

  /// Asks the game to quit, then kills it after [grace].
  Future<void> stop({Duration? grace});

  Future<void> dispose();
}

/// The real handle: one child process, its two output streams and its exit code.
///
/// Four things this does that `Process.start` + `listen(print)` gets wrong:
///
///  * **Lines, not chunks.** A JVM flushes when its buffer fills, so a chunk
///    boundary lands mid-line as a matter of course. Each stream is buffered and
///    split, and the trailing partial line is flushed on close — otherwise the
///    last line of a crashed game, the one with the stack trace, is dropped.
///  * **Multi-byte characters.** Decoding each chunk independently throws on a
///    code point split across a boundary; the game logs Chinese and emoji. A
///    chunked UTF-8 decoder carries the partial sequence.
///  * **Drain before exit.** `exitCode` resolves before the tail of stderr has
///    been delivered. Reporting the exit first loses the crash reason.
///  * **Bounded history.** A modded game emits hundreds of thousands of lines;
///    keeping them all is an out-of-memory bug that only shows up after an hour.
class ProcessLaunchHandle implements LaunchHandle {
  ProcessLaunchHandle({
    required this.prepare,
    ProcessStarter? starter,
    this.historyLimit = 2000,
    this.defaultGrace = const Duration(seconds: 5),
    this.drainTimeout = const Duration(seconds: 2),
  }) : _starter = starter ?? _defaultStarter;

  /// Test-only seam: a handle whose plan always refuses, without a filesystem.
  factory ProcessLaunchHandle.refusing(
    LaunchRefused outcome, {
    ProcessStarter? starter,
  }) => ProcessLaunchHandle(prepare: () async => outcome, starter: starter);

  /// Produces a runnable plan, or the blockers that refuse it. Runs inside
  /// `preparing`, so an install or verify step can live here and fail cleanly.
  final Future<LaunchOutcome> Function() prepare;

  final ProcessStarter _starter;

  final int historyLimit;
  final Duration defaultGrace;

  /// How long to wait for the output pipes after the process exits.
  final Duration drainTimeout;

  final _controller = StreamController<LaunchEvent>.broadcast();
  final _recent = <LaunchLog>[];

  LaunchState _state = LaunchState.idle;
  Process? _process;
  int? _exitCode;
  bool _starting = false;
  DateTime? _startedAt;
  bool _disposed = false;

  @override
  LaunchState get state => _state;

  @override
  Stream<LaunchEvent> get events => _controller.stream;

  @override
  List<LaunchLog> get recentLog => List.unmodifiable(_recent);

  @override
  int? get exitCode => _exitCode;

  void _emit(LaunchEvent event) {
    if (_controller.isClosed) return;
    if (event is LaunchLog) {
      _recent.add(event);
      if (_recent.length > historyLimit) {
        _recent.removeRange(0, _recent.length - historyLimit);
      }
    }
    _controller.add(event);
  }

  void _setState(LaunchState next) {
    if (_state == next) return;
    _state = next;
    _emit(LaunchStateChanged(next));
  }

  void _fail(
    LaunchFailure failure,
    String detail, {
    List<LaunchBlocker> blockers = const [],
  }) {
    _emit(LaunchLog(detail, channel: LogChannel.launcher));
    _setState(LaunchState.exited);
    _emit(
      LaunchEnded(
        exitCode: null,
        uptime: Duration.zero,
        failure: failure,
        blockers: blockers,
      ),
    );
  }

  @override
  Future<void> start() async {
    if (_disposed ||
        _starting ||
        _state == LaunchState.preparing ||
        _state == LaunchState.running ||
        _state == LaunchState.stopping) {
      return;
    }
    _starting = true;
    _setState(LaunchState.preparing);

    final LaunchOutcome outcome;
    try {
      outcome = await prepare();
    } catch (e) {
      _fail(LaunchFailure.prepareFailed, 'prepare failed: $e');
      _starting = false;
      return;
    }

    if (outcome is! LaunchReady) {
      final blockers = (outcome as LaunchRefused).blockers;
      for (final b in blockers) {
        _emit(
          LaunchLog(
            '${b.code.name}: ${b.message}',
            channel: LogChannel.launcher,
          ),
        );
      }
      _fail(
        LaunchFailure.refused,
        'launch refused by ${blockers.length} blocker(s)',
        blockers: blockers,
      );
      _starting = false;
      return;
    }

    final plan = outcome.plan;
    _emit(
      LaunchLog(
        // The access token is deliberately absent from `commandLine`.
        plan.commandLine.join(' '),
        channel: LogChannel.launcher,
      ),
    );

    try {
      final process = await _starter(
        plan.executable,
        plan.args,
        workingDirectory: plan.workingDirectory,
      );
      _process = process;
      _startedAt = DateTime.now();
      _setState(LaunchState.running);

      final drained = Future.wait([
        _pump(process.stdout, LogChannel.stdout),
        _pump(process.stderr, LogChannel.stderr),
      ]);

      final exit = await process.exitCode;
      // Do not await forever: a grandchild can inherit the pipe and keep it
      // open after the game is gone, and a launcher that never notices its game
      // exited is stuck with a stop button that does nothing. Whatever arrived
      // before the drain timeout is still delivered.
      await drained.timeout(drainTimeout, onTimeout: () => const <void>[]);

      _exitCode = exit;
      _setState(LaunchState.exited);
      _emit(LaunchEnded(exitCode: exit, uptime: _uptime()));
    } on ProcessException catch (e) {
      _fail(LaunchFailure.spawnFailed, 'could not start: ${e.message}');
    } on FileSystemException catch (e) {
      _fail(LaunchFailure.spawnFailed, 'could not start: ${e.message}');
    } finally {
      _starting = false;
    }
  }

  Duration _uptime() => _startedAt == null
      ? Duration.zero
      : DateTime.now().difference(_startedAt!);

  /// Splits [stream] into lines with a UTF-8 decoder and a line buffer, and
  /// completes once the stream is closed *and* the tail has been flushed.
  Future<void> _pump(Stream<List<int>> stream, LogChannel channel) {
    final buffer = StringBuffer();
    final decoder = const Utf8Decoder(allowMalformed: true)
        .startChunkedConversion(_StringSinkAdapter(buffer));

    void flushLines({required bool isFinal}) {
      final text = buffer.toString();
      buffer.clear();
      if (text.isEmpty) return;
      final parts = text.split('\n');
      // The last part is either an incomplete line or (when the chunk ended with
      // a newline) an empty string; both are handled by keeping it back.
      final tail = parts.removeLast();
      for (final line in parts) {
        _emit(LaunchLog(_stripCr(line), channel: channel));
      }
      if (isFinal) {
        if (tail.isNotEmpty) {
          _emit(LaunchLog(_stripCr(tail), channel: channel));
        }
      } else {
        buffer.write(tail);
      }
    }

    return () async {
      await for (final chunk in stream) {
        decoder.add(chunk);
        flushLines(isFinal: false);
      }
      decoder.close();
      flushLines(isFinal: true);
    }();
  }

  @override
  Future<void> stop({Duration? grace}) async {
    final process = _process;
    if (process == null || _state != LaunchState.running) {
      if (_state == LaunchState.preparing) {
        // Honest rather than silent: the reported bug would otherwise be "stop
        // does nothing" with no trace in the console.
        _emit(
          LaunchLog(
            'stop requested before the process existed',
            channel: LogChannel.launcher,
          ),
        );
      }
      return;
    }

    _setState(LaunchState.stopping);
    final effectiveGrace = grace ?? defaultGrace;

    // The client does not read stdin, so the only graceful signal available is
    // SIGTERM, which is what `kill()` sends on POSIX. Windows has no SIGTERM and
    // terminates immediately, which is why the grace period is not assumed to
    // have been honoured there.
    process.kill();

    final exited = await Future.any<bool>([
      process.exitCode.then((_) => true),
      Future<bool>.delayed(effectiveGrace, () => false),
    ]);
    if (!exited) {
      _emit(
        LaunchLog(
          'did not exit within ${effectiveGrace.inSeconds}s; killing',
          channel: LogChannel.launcher,
        ),
      );
      process.kill(ProcessSignal.sigkill);
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final process = _process;
    if (process != null && _state != LaunchState.exited) {
      process.kill(ProcessSignal.sigkill);
    }
    await _controller.close();
  }
}

/// Adapts a `StringBuffer` to the `Sink<String>` a chunked decoder wants.
class _StringSinkAdapter implements Sink<String> {
  _StringSinkAdapter(this._buffer);

  final StringBuffer _buffer;

  @override
  void add(String data) => _buffer.write(data);

  @override
  void close() {}
}

String _stripCr(String line) =>
    line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
