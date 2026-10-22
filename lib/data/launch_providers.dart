import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/instance/instance.dart';
import '../../core/launch/launch_handle.dart';
import '../../core/mc/arch_compat.dart';
import 'instance_providers.dart';

/// Builds a handle for [instance]. Overridden at startup with the real
/// `ProcessLaunchHandle`; tests substitute a fake so no JVM is involved.
typedef LaunchHandleFactory = LaunchHandle Function(Instance instance);

final launchHandleFactoryProvider = Provider<LaunchHandleFactory>(
  (ref) => throw StateError(
    'launchHandleFactoryProvider must be overridden at startup',
  ),
);

/// The launch session the UI watches.
///
/// Holds one handle at a time: a second launch while one is running would mean
/// two games fighting over the same `logs/latest.log` and the same options file,
/// so the UI disables play instead of allowing it.
class LaunchController extends Notifier<LaunchSession> {
  LaunchHandle? _handle;
  StreamSubscription<LaunchEvent>? _sub;
  Instance? _instance;
  DateTime? _startedAt;

  @override
  LaunchSession build() {
    ref.onDispose(() {
      _sub?.cancel();
      _handle?.dispose();
      _handle = null;
    });
    return const LaunchSession.idle();
  }

  /// The instance currently running or last run.
  Instance? get instance => _instance;

  /// Starts [instance]. A no-op when something is already running.
  Future<void> launch(Instance instance) async {
    if (state.isBusy) return;

    _instance = instance;
    final handle = ref.read(launchHandleFactoryProvider)(instance);
    _handle = handle;
    state = LaunchSession(
      state: LaunchState.preparing,
      log: const [],
      instanceId: instance.id,
    );

    _sub = handle.events.listen(_onEvent);
    await handle.start();
  }

  void _onEvent(LaunchEvent event) {
    switch (event) {
      case LaunchLog(:final text, :final channel):
        final current = state;
        final log = [...current.log, LogLine(text, channel)];
        state = LaunchSession(
          state: current.state,
          // Keep the *newest* lines. `take()` would pin the first 2000 lines of
          // a modded session and silently stop showing anything new, which looks
          // exactly like the game hanging.
          log: log.length > _maxLines
              ? log.sublist(log.length - _maxLines)
              : log,
          instanceId: current.instanceId,
          exitCode: current.exitCode,
        );
      case LaunchStateChanged(state: final next):
        final current = state;
        if (next == LaunchState.running) _startedAt = DateTime.now();
        state = LaunchSession(
          state: next,
          log: current.log,
          instanceId: current.instanceId,
          exitCode: current.exitCode,
        );
      case LaunchEnded(
        :final exitCode,
        :final uptime,
        :final failure,
        :final blockers,
      ):
        final current = state;
        // The playtime comes from the process's own uptime, not from when the
        // launcher noticed: a stalled frame must not add minutes to the total.
        final session = uptime > Duration.zero ? uptime : _sessionSinceStart();
        state = LaunchSession(
          state: LaunchState.exited,
          log: current.log,
          instanceId: current.instanceId,
          exitCode: exitCode,
          failure: failure,
          blockers: blockers,
          uptime: session,
          endedSession: session,
        );
        // Recorded here, at the single place a session ends, rather than by a
        // widget listening for the same transition: two listeners would double
        // the playtime, and a screen that is not mounted would record none.
        final id = current.instanceId;
        if (id != null && session > Duration.zero) {
          ref.read(instanceListProvider.notifier).recordSession(id, session);
        }
        _startedAt = null;
        _sub?.cancel();
        _sub = null;
        _handle = null;
    }
  }

  Duration _sessionSinceStart() {
    final started = _startedAt;
    return started == null ? Duration.zero : DateTime.now().difference(started);
  }

  Future<void> stop() async {
    await _handle?.stop();
  }

  static const _maxLines = 2000;
}

/// Everything the launch UI renders, in one immutable value.
class LaunchSession {
  const LaunchSession({
    required this.state,
    required this.log,
    this.instanceId,
    this.exitCode,
    this.failure,
    this.blockers = const [],
    this.uptime = Duration.zero,
    this.endedSession,
  });

  const LaunchSession.idle()
    : state = LaunchState.idle,
      log = const [],
      instanceId = null,
      exitCode = null,
      failure = null,
      blockers = const [],
      uptime = Duration.zero,
      endedSession = null;

  final LaunchState state;
  final List<LogLine> log;
  final String? instanceId;
  final int? exitCode;
  final LaunchFailure? failure;

  /// Why the launch was refused, when [failure] is [LaunchFailure.refused].
  ///
  /// Kept so the play screen can offer the fix (download Java, reinstall) rather
  /// than only reporting that it did not work.
  final List<LaunchBlocker> blockers;

  /// How long the last session ran. Zero while running.
  final Duration uptime;

  /// Set once when a session ends, so the screen can record playtime exactly
  /// once without a second watcher racing it.
  final Duration? endedSession;

  bool get isBusy =>
      state == LaunchState.preparing ||
      state == LaunchState.running ||
      state == LaunchState.stopping;

  bool get canStop => state == LaunchState.running;

  LaunchSession copyWith({Duration? endedSession}) => LaunchSession(
    state: state,
    log: log,
    instanceId: instanceId,
    exitCode: exitCode,
    failure: failure,
    uptime: uptime,
    endedSession: endedSession ?? this.endedSession,
  );
}

class LogLine {
  const LogLine(this.text, this.channel);

  final String text;
  final LogChannel channel;
}

final launchControllerProvider =
    NotifierProvider<LaunchController, LaunchSession>(LaunchController.new);
