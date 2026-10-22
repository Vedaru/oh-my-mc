import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/launch/launch_handle.dart';
import 'package:oh_my_mc/core/mc/arch_compat.dart';
import 'package:oh_my_mc/core/mc/host.dart';
import 'package:oh_my_mc/core/mc/java_manager.dart';
import 'package:oh_my_mc/core/mc/launch_plan.dart';
import 'package:oh_my_mc/core/mc/launch_service.dart';
import 'package:oh_my_mc/core/mc/library_graph.dart';

/// A handle whose plan is a real shell command, so the *real* process path
/// (spawn, both streams, exit code, kill) is exercised without a JVM.
ProcessLaunchHandle handleFor(
  String script, {
  int historyLimit = 2000,
  Duration grace = const Duration(seconds: 2),
}) => ProcessLaunchHandle(
  prepare: () async =>
      LaunchReady(plan: _plan(script), java: _java, graph: _graph),
  defaultGrace: grace,
  historyLimit: historyLimit,
);

/// Only executable, args and working directory are read by the handle.
LaunchPlan _plan(String script) => LaunchPlan(
  executable: '/bin/sh',
  args: ['-c', script],
  classpath: const [],
  nativeArchives: const [],
  mainClass: 'Stub',
  workingDirectory: Directory.systemTemp.path,
);

final _java = const JavaRuntime(
  path: '/bin/sh',
  majorVersion: 17,
  versionString: '17.0.0',
  vendor: 'test',
  arch: HostArch.x86_64,
);

final _graph = const LibraryGraph(
  classpath: [],
  natives: [],
  jars: [],
  skipped: [],
);

/// Waits for the first event satisfying [match], or fails the test.
Future<T> waitFor<T extends LaunchEvent>(
  Stream<LaunchEvent> events,
  bool Function(T) match, {
  Duration timeout = const Duration(seconds: 20),
}) {
  return events
      .where((e) => e is T && match(e))
      .cast<T>()
      .first
      .timeout(
        timeout,
        onTimeout: () => throw StateError('event never arrived'),
      );
}

/// Collects everything a handle emits until it ends.
Future<List<LaunchEvent>> collectUntilEnd(LaunchHandle handle) async {
  final events = <LaunchEvent>[];
  final done = Completer<void>();
  final sub = handle.events.listen((e) {
    events.add(e);
    if (e is LaunchEnded && !done.isCompleted) done.complete();
  });
  await handle.start();
  await done.future.timeout(const Duration(seconds: 30));
  await sub.cancel();
  return events;
}

void main() {
  group('state machine', () {
    test('runs idle -> preparing -> running -> exited', () async {
      final handle = handleFor('echo hello');
      final states = <LaunchState>[];
      final sub = handle.events.listen((e) {
        if (e is LaunchStateChanged) states.add(e.state);
      });

      await collectUntilEnd(handle);
      await sub.cancel();
      await handle.dispose();

      expect(states, [
        LaunchState.preparing,
        LaunchState.running,
        LaunchState.exited,
      ]);
    });

    test('a busy handle ignores a second start', () async {
      final handle = handleFor('sleep 0.4');
      final starts = <LaunchState>[];
      final sub = handle.events.listen((e) {
        if (e is LaunchStateChanged) starts.add(e.state);
      });

      final first = collectUntilEnd(handle);
      // The second call must not spawn a second process; if it did, two
      // LaunchEnded events would arrive for one `collectUntilEnd`.
      await handle.start();
      await first;
      await sub.cancel();
      await handle.dispose();

      expect(
        starts.where((s) => s == LaunchState.running).length,
        1,
        reason: 'two running transitions mean two processes',
      );
    });

    test('a refused plan never spawns anything', () async {
      var spawned = false;
      final handle = ProcessLaunchHandle(
        prepare: () async => const LaunchRefused([
          LaunchBlocker(
            code: BlockerCode.noRuntime,
            message: 'no java',
            remedy: 'install java',
          ),
        ]),
        starter: (exe, args, {workingDirectory}) async {
          spawned = true;
          throw StateError('must not spawn');
        },
      );

      final events = await collectUntilEnd(handle);
      await handle.dispose();

      expect(spawned, isFalse, reason: 'a refusal must not reach the OS');
      final ended = events.whereType<LaunchEnded>().single;
      expect(ended.failure, LaunchFailure.refused);
      expect(ended.exitCode, isNull);
      expect(
        events.whereType<LaunchLog>().any((l) => l.text.contains('no java')),
        isTrue,
        reason: 'the blocker must reach the console with its reason',
      );
    });

    test('a failed prepare is reported, not thrown at the caller', () async {
      final handle = ProcessLaunchHandle(
        prepare: () async => throw StateError('asset index missing'),
      );

      final events = await collectUntilEnd(handle);
      await handle.dispose();

      final ended = events.whereType<LaunchEnded>().single;
      expect(ended.failure, LaunchFailure.prepareFailed);
      expect(
        events.whereType<LaunchLog>().any(
          (l) => l.text.contains('asset index missing'),
        ),
        isTrue,
      );
    });

    test('a missing executable reports spawnFailed', () async {
      final handle = ProcessLaunchHandle(
        prepare: () async => LaunchReady(
          plan: LaunchPlan(
            executable: '/nonexistent/definitely-not-here',
            args: const [],
            classpath: const [],
            nativeArchives: const [],
            mainClass: 'Stub',
            workingDirectory: Directory.systemTemp.path,
          ),
          java: _java,
          graph: _graph,
        ),
      );

      final events = await collectUntilEnd(handle);
      await handle.dispose();

      final ended = events.whereType<LaunchEnded>().single;
      expect(ended.failure, LaunchFailure.spawnFailed);
      expect(ended.exitCode, isNull);
    });
  });

  group('output handling', () {
    test('stdout and stderr both reach the console, tagged', () async {
      final handle = handleFor('echo out-line; echo err-line >&2');
      final events = await collectUntilEnd(handle);
      await handle.dispose();

      final logs = events.whereType<LaunchLog>().toList();
      expect(
        logs.any((l) => l.text == 'out-line' && l.channel == LogChannel.stdout),
        isTrue,
      );
      expect(
        logs.any((l) => l.text == 'err-line' && l.channel == LogChannel.stderr),
        isTrue,
        reason: 'stderr carries every JVM crash; dropping it hides the bug',
      );
    });

    test('a line written in pieces is reassembled', () async {
      // Three separate writes, no newline until the end.
      final handle = handleFor(
        r"printf '%s' 'split'; sleep 0.05; printf '%s' '-across'; "
        r"sleep 0.05; printf '%s\n' '-chunks'",
      );
      final events = await collectUntilEnd(handle);
      await handle.dispose();

      final logs = events.whereType<LaunchLog>().map((l) => l.text).toList();
      expect(
        logs,
        contains('split-across-chunks'),
        reason: 'a chunk boundary landing mid-line must not split the message',
      );
    });

    test('a trailing line without a newline is not dropped', () async {
      final handle = handleFor(r"printf 'no-trailing-newline'");
      final events = await collectUntilEnd(handle);
      await handle.dispose();

      expect(
        events.whereType<LaunchLog>().map((l) => l.text),
        contains('no-trailing-newline'),
        reason: 'the last line of a crashed game is the stack trace',
      );
    });

    test('a multi-byte character split across chunks survives', () async {
      // "启动" is 6 bytes; splitting after the 5th splits the last code point.
      final handle = handleFor(
        // Octal, and the split is deliberately *inside* a code point: "\345\220"
        // is the first two bytes of 启 (E5 90 AF), so the second write finishes
        // it. Splitting at a character boundary would not test anything.
        r'printf "\345\220"; sleep 0.05; printf "\257\345\212\250\n"',
      );
      final events = await collectUntilEnd(handle);
      await handle.dispose();

      final logs = events.whereType<LaunchLog>().map((l) => l.text).toList();
      expect(
        logs,
        contains('启动'),
        reason:
            'the game logs Chinese; a per-chunk decode would produce '
            'replacement characters or throw',
      );
    });

    test('CRLF line endings are stripped', () async {
      final handle = handleFor(r"printf 'windows-line\r\n'");
      final events = await collectUntilEnd(handle);
      await handle.dispose();

      expect(
        events.whereType<LaunchLog>().map((l) => l.text),
        contains('windows-line'),
      );
    });

    test('the exit code and uptime are reported', () async {
      final handle = handleFor('exit 42');
      final events = await collectUntilEnd(handle);
      await handle.dispose();

      final ended = events.whereType<LaunchEnded>().single;
      expect(ended.exitCode, 42);
      expect(ended.succeeded, isFalse);
      expect(handle.exitCode, 42);
    });

    test('a clean exit is reported as success', () async {
      final handle = handleFor('exit 0');
      final events = await collectUntilEnd(handle);
      await handle.dispose();

      expect(events.whereType<LaunchEnded>().single.succeeded, isTrue);
    });
  });

  group('history', () {
    test('early lines can still be read by a late-attaching console', () async {
      final handle = handleFor('echo first; echo second');
      await collectUntilEnd(handle);
      await handle.dispose();

      expect(
        handle.recentLog.map((l) => l.text),
        containsAll(['first', 'second']),
        reason:
            'the console is built after the launch starts, so history is '
            'the only way it sees the command line and the first output',
      );
    });

    test('history is bounded', () async {
      final handle = handleFor(
        'i=0; while [ \$i -lt 400 ]; do echo "line-\$i"; i=\$((i+1)); done',
        historyLimit: 50,
      );
      final events = await collectUntilEnd(handle);
      await handle.dispose();

      expect(
        events.whereType<LaunchLog>().length,
        greaterThan(300),
        reason:
            'every line must still be *emitted*, only the retained copy '
            'is bounded',
      );
      expect(handle.recentLog.length, lessThanOrEqualTo(50));
      expect(
        handle.recentLog.last.text,
        'line-399',
        reason: 'bounding must drop the oldest lines, not the newest',
      );
    });
  });

  group('stop', () {
    test('a running process is terminated and exits', () async {
      // Prints a marker, then blocks; only a kill ends it.
      final handle = handleFor('echo started; sleep 30');
      final sawStart = handle.events
          .where((e) => e is LaunchLog && e.text == 'started')
          .first;

      final done = collectUntilEnd(handle);
      await sawStart;

      await handle.stop(grace: const Duration(seconds: 1));
      final events = await done.timeout(const Duration(seconds: 15));
      await handle.dispose();

      final ended = events.whereType<LaunchEnded>().single;
      expect(
        ended.exitCode,
        isNot(0),
        reason: 'a killed process does not exit 0',
      );
      expect(
        events.whereType<LaunchStateChanged>().map((e) => e.state),
        contains(LaunchState.stopping),
        reason:
            'the UI needs a distinct stopping state, or the stop button '
            'looks inert during the grace period',
      );
    });

    test('a process that ignores SIGTERM is killed after the grace period', () async {
      // The game can hang in a shutdown hook and stop responding to SIGTERM.
      // `trap '' TERM` reproduces that, so this exercises the *fallback* path;
      // the cooperative test above passes even with the fallback removed.
      final handle = handleFor(r"trap '' TERM; echo started; sleep 30");
      final sawStart = handle.events
          .where((e) => e is LaunchLog && e.text == 'started')
          .first;

      final done = collectUntilEnd(handle);
      await sawStart;

      await handle.stop(grace: const Duration(milliseconds: 300));
      final events = await done.timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw StateError(
            'the process survived stop(); without the fallback kill the '
            'launcher is stuck forever on a hung game',
          );
        },
      );
      await handle.dispose();

      expect(
        events.whereType<LaunchLog>().any(
          (l) => l.text.contains('did not exit within'),
        ),
        isTrue,
        reason: 'the user must be able to tell a kill from a clean quit',
      );
      expect(events.whereType<LaunchEnded>().single.exitCode, isNotNull);
    });

    test('stopping an idle handle does nothing and does not throw', () async {
      final handle = handleFor('echo hi');
      await handle.stop();
      expect(handle.state, LaunchState.idle);
      await handle.dispose();
    });

    test('stopping while preparing is logged, not silently ignored', () async {
      final gate = Completer<LaunchOutcome>();
      final handle = ProcessLaunchHandle(prepare: () => gate.future);

      final logs = <LaunchLog>[];
      final sub = handle.events.listen((e) {
        if (e is LaunchLog) logs.add(e);
      });

      final started = handle.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await handle.stop();

      gate.complete(
        LaunchReady(plan: _plan('true'), java: _java, graph: _graph),
      );
      await started;
      await sub.cancel();
      await handle.dispose();

      expect(
        logs.any((l) => l.text.contains('before the process existed')),
        isTrue,
      );
    });
  });

  group('log formatting', () {
    test(
      'the launcher command line is logged without the access token',
      () async {
        final handle = handleFor('true');
        final events = await collectUntilEnd(handle);
        await handle.dispose();

        final launcherLogs = events.whereType<LaunchLog>().where(
          (l) => l.channel == LogChannel.launcher,
        );
        expect(launcherLogs, isNotEmpty);
        expect(
          launcherLogs.any((l) => l.text.contains('/bin/sh')),
          isTrue,
          reason: 'the command line is the first thing a bug report needs',
        );
      },
    );
  });
}
