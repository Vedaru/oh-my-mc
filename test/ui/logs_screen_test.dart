import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/app/providers.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/core/launch/launch_handle.dart';
import 'package:oh_my_mc/core/logs/log_files.dart';
import 'package:oh_my_mc/data/instance_providers.dart';
import 'package:oh_my_mc/data/instance_store.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/data/launch_providers.dart';
import 'package:oh_my_mc/data/log_providers.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:oh_my_mc/ui/logs/logs_screen.dart';
import 'package:path/path.dart' as p;

import '../support/harness.dart';

/// A scripted session so the live-log side of the page can be asserted without a
/// process.
class _ScriptedLaunch extends LaunchController {
  _ScriptedLaunch(this.lines);

  final List<String> lines;

  @override
  LaunchSession build() => LaunchSession(
    state: LaunchState.exited,
    log: [for (final line in lines) LogLine(line, LogChannel.stdout)],
    instanceId: 'a',
  );
}

LogFile logFile(String path, String label, DateTime modified) => LogFile(
  file: File(path),
  label: label,
  modified: modified,
  isInstall: false,
);

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('logs-screen');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    List<LogFile> files = const [],
    Map<String, List<LogEntry>> tails = const {},
    List<String> live = const [],
  }) async {
    final container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWith(
          (ref) => MemorySettingsStore(AppSettings.defaults),
        ),
        instanceStoreProvider.overrideWith(
          (ref) => MemoryInstanceStore([
            Instance(id: 'a', name: 'Demo', versionId: '1.20.1'),
          ]),
        ),
        launcherPathsProvider.overrideWithValue(
          LauncherPaths(data: tmp, game: Directory(p.join(tmp.path, 'game'))),
        ),
        launchControllerProvider.overrideWith(() => _ScriptedLaunch(live)),
        logFilesProvider.overrideWith((ref) async => files),
        // A family override answers every path the page asks for.
        logTailProvider.overrideWith(
          (ref, path) async => tails[path] ?? const [],
        ),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpScreen(tester, container, const LogsScreen());
    return container;
  }

  testWidgets('saved sessions are listed, newest first', (tester) async {
    await pump(
      tester,
      files: [
        logFile('/logs/launch-new.log', '26.3 · 23:58', DateTime(2026, 10, 22)),
        logFile(
          '/logs/launch-old.log',
          '1.19.2 · 18:04',
          DateTime(2026, 10, 20),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('26.3 · 23:58'), findsOneWidget);
    expect(find.text('1.19.2 · 18:04'), findsOneWidget);
    // No output yet, so there is no "current session" entry to click.
    expect(find.text('Current session'), findsNothing);
  });

  testWidgets('opening a saved session shows its lines', (tester) async {
    await pump(
      tester,
      files: [
        logFile('/logs/launch-new.log', '26.3 · 23:58', DateTime(2026, 10, 22)),
      ],
      tails: {
        '/logs/launch-new.log': const [
          LogEntry('[23:58:14] [Render thread/INFO]: Backend library: LWJGL'),
          LogEntry('java.lang.RuntimeException: boom', isStderr: true),
        ],
      },
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('26.3 · 23:58'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Backend library'),
      findsOneWidget,
      reason: 'a saved session has to be readable, not just listed',
    );
  });

  testWidgets('the live session is offered while it has output', (
    tester,
  ) async {
    await pump(tester, live: ['[23:59:00] [main/INFO]: hello']);
    await tester.pumpAndSettle();

    // The console shows the live log without asking: the user came here from a
    // launch.
    expect(find.textContaining('hello'), findsOneWidget);
    expect(find.text('Current session'), findsOneWidget);
  });

  testWidgets('the errors filter keeps stderr from a saved session', (
    tester,
  ) async {
    await pump(
      tester,
      files: [
        logFile('/logs/launch-new.log', '26.3 · 23:58', DateTime(2026, 10, 22)),
      ],
      tails: {
        '/logs/launch-new.log': const [
          LogEntry('[23:58:14] [main/INFO]: all good'),
          LogEntry('Exception in thread "main"', isStderr: true),
        ],
      },
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('26.3 · 23:58'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(m3.Switch));
    await tester.pumpAndSettle();

    expect(find.textContaining('Exception in thread'), findsOneWidget);
    expect(find.textContaining('all good'), findsNothing);
  });
}
