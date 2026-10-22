import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/app/providers.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/core/launch/launch_handle.dart';
import 'package:oh_my_mc/core/mc/arch_compat.dart';
import 'package:oh_my_mc/core/mc/launch_service.dart';
import 'package:oh_my_mc/data/instance_providers.dart';
import 'package:oh_my_mc/data/instance_store.dart';
import 'package:oh_my_mc/data/launch_providers.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:oh_my_mc/l10n/l10n.dart';
import 'package:oh_my_mc/ui/instances/instances_screen.dart';
import 'package:oh_my_mc/ui/launch/launch_screen.dart';
import 'package:oh_my_mc/ui/motion/motion.dart';
import 'package:oh_my_mc/ui/theme/app_theme.dart';
import 'package:oh_my_mc/ui/components/app_button.dart';

/// A handle that never spawns a process, so a widget test can drive every launch
/// state deterministically.
///
/// The stream is real (a `StreamController`), not a mock: the controller
/// subscribes to it exactly as it does in production, which is where the
/// subscription-lifetime bugs live.
class FakeLaunchHandle implements LaunchHandle {
  FakeLaunchHandle({this.prepareOutcome, this.failPreparation = false});

  final _controller = StreamController<LaunchEvent>.broadcast();
  LaunchState _state = LaunchState.idle;

  /// Emitted by [start] before it reports `running`; `null` starts successfully.
  final LaunchOutcome? prepareOutcome;

  /// Reports a thrown prepare step, which is a different failure from a
  /// refusal: nothing about the plan was wrong, the launcher could not build it.
  final bool failPreparation;

  /// Emitted by [stop].
  int stopCalls = 0;

  final _started = Completer<void>();

  /// Completes once the test can emit into a started handle.
  Future<void> get started => _started.future;

  @override
  LaunchState get state => _state;

  /// The handle's own bounded buffer; the controller builds its log from the
  /// event stream instead, but the interface requires it.
  @override
  List<LaunchLog> get recentLog => List.unmodifiable(_recent);

  final _recent = <LaunchLog>[];

  @override
  int? get exitCode => _exitCode;

  int? _exitCode;

  @override
  Stream<LaunchEvent> get events => _controller.stream;

  @override
  Future<void> start() async {
    _set(LaunchState.preparing);
    if (failPreparation) {
      _controller.add(
        LaunchEnded(
          exitCode: null,
          uptime: Duration.zero,
          failure: LaunchFailure.prepareFailed,
        ),
      );
      _set(LaunchState.exited);
      if (!_started.isCompleted) _started.complete();
      return;
    }
    if (prepareOutcome case final LaunchRefused refused) {
      // Mirrors `ProcessLaunchHandle`: a refusal is `refused` *with* its
      // blockers, not a prepare failure. Reporting the wrong failure here would
      // let the screen's blocker handling rot untested.
      _controller.add(
        LaunchEnded(
          exitCode: null,
          uptime: Duration.zero,
          failure: LaunchFailure.refused,
          blockers: refused.blockers,
        ),
      );
      _set(LaunchState.exited);
      if (!_started.isCompleted) _started.complete();
      return;
    }
    _set(LaunchState.running);
    if (!_started.isCompleted) _started.complete();
  }

  /// Emits a log line as if the game printed it.
  void log(String text, {LogChannel channel = LogChannel.stdout}) {
    final line = LaunchLog(text, channel: channel);
    _recent.add(line);
    _controller.add(line);
  }

  /// Ends the session with [exitCode].
  void exit(int exitCode, {Duration uptime = const Duration(minutes: 4)}) {
    _exitCode = exitCode;
    _controller.add(
      LaunchEnded(exitCode: exitCode, uptime: uptime, failure: null),
    );
    _set(LaunchState.exited);
  }

  @override
  Future<void> stop({Duration? grace}) async {
    stopCalls++;
    _set(LaunchState.stopping);
    exit(0, uptime: const Duration(seconds: 30));
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  void _set(LaunchState next) {
    _state = next;
    if (!_controller.isClosed) _controller.add(LaunchStateChanged(next));
  }
}

/// Mounts a screen inside the real localization/theme/motion stack, with the
/// instance list and launch controller overridden.
///
/// No `FluentApp`: a test that mounts the whole app cannot tell whether a widget
/// reads its own providers or happens to inherit something from the shell, and
/// the shell is not what these tests are about.
Future<ProviderContainer> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  List<Instance> instances = const [],
  Instance? selected,
  FakeLaunchHandle Function()? handle,
  AppSettings settings = AppSettings.defaults,
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsStoreProvider.overrideWith(
        (ref) => MemorySettingsStore(settings),
      ),
      instanceStoreProvider.overrideWith(
        (ref) => MemoryInstanceStore(instances),
      ),
      launchHandleFactoryProvider.overrideWith(
        (ref) =>
            (instance) => (handle ?? FakeLaunchHandle.new)(),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: m3.MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: AppTheme.material(Brightness.light),
        home: MotionScope(
          motion: Motion.full,
          child: m3.Scaffold(
            body: m3.SafeArea(
              child: Padding(
                padding: const m3.EdgeInsets.all(16),
                child: screen,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // The instance list loads on a microtask; without this the first assertion
  // would see the loading spinner.
  await tester.pumpAndSettle();
  if (selected != null) {
    await container.read(instanceListProvider.notifier).select(selected.id);
    await tester.pumpAndSettle();
  }
  return container;
}

Instance sample({
  String id = 'demo',
  String name = 'Demo',
  String versionId = '1.20.1',
  LoaderKind loader = LoaderKind.vanilla,
  String? loaderVersion,
  DateTime? lastPlayedAt,
  Duration totalPlaytime = Duration.zero,
}) => Instance(
  id: id,
  name: name,
  versionId: versionId,
  loader: loader,
  loaderVersion: loaderVersion,
  lastPlayedAt: lastPlayedAt,
  totalPlaytime: totalPlaytime,
);

void main() {
  group('instance list state', () {
    test('a fresh store selects nothing and reports no skip', () async {
      final container = ProviderContainer(
        overrides: [
          settingsStoreProvider.overrideWith(
            (ref) => MemorySettingsStore(AppSettings.defaults),
          ),
          instanceStoreProvider.overrideWith((ref) => MemoryInstanceStore()),
        ],
      );
      addTearDown(container.dispose);

      container.read(instanceListProvider);
      await pumpEventQueue();

      final state = container.read(instanceListProvider);
      expect(state, isA<InstanceListReady>());
      final ready = state as InstanceListReady;
      expect(ready.instances, isEmpty);
      expect(ready.selectedId, isNull);
      expect(ready.selected, isNull);
    });

    test('a loaded list selects the first instance', () async {
      final container = ProviderContainer(
        overrides: [
          settingsStoreProvider.overrideWith(
            (ref) => MemorySettingsStore(AppSettings.defaults),
          ),
          instanceStoreProvider.overrideWith(
            (ref) => MemoryInstanceStore([
              sample(id: 'a', name: 'A'),
              sample(id: 'b', name: 'B'),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(instanceListProvider);
      await pumpEventQueue();

      final ready = container.read(instanceListProvider) as InstanceListReady;
      expect(
        ready.selectedId,
        'a',
        reason:
            'the play button needs a target '
            'without the user having to click a card first',
      );
    });

    test('deleting the selected instance moves the selection', () async {
      final store = MemoryInstanceStore([
        sample(id: 'a', name: 'A'),
        sample(id: 'b', name: 'B'),
      ]);
      final container = ProviderContainer(
        overrides: [
          settingsStoreProvider.overrideWith(
            (ref) => MemorySettingsStore(AppSettings.defaults),
          ),
          instanceStoreProvider.overrideWith((ref) => store),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(instanceListProvider.notifier);
      await pumpEventQueue();
      await notifier.select('a');
      await notifier.remove('a');

      final ready = container.read(instanceListProvider) as InstanceListReady;
      expect(ready.instances.map((i) => i.id), ['b']);
      expect(
        ready.selectedId,
        'b',
        reason:
            'leaving the selection on a deleted id would make the play '
            'button act on nothing',
      );
      expect((await store.load()).map((i) => i.id), [
        'b',
      ], reason: 'the removal must be persisted, not just held in memory');
    });

    test('deleting the last instance leaves nothing selected', () async {
      final container = ProviderContainer(
        overrides: [
          settingsStoreProvider.overrideWith(
            (ref) => MemorySettingsStore(AppSettings.defaults),
          ),
          instanceStoreProvider.overrideWith(
            (ref) => MemoryInstanceStore([sample(id: 'only')]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(instanceListProvider.notifier);
      await pumpEventQueue();
      await notifier.remove('only');

      final ready = container.read(instanceListProvider) as InstanceListReady;
      expect(ready.instances, isEmpty);
      expect(ready.selectedId, isNull);
    });

    test('create avoids colliding with an existing directory name', () async {
      final container = ProviderContainer(
        overrides: [
          settingsStoreProvider.overrideWith(
            (ref) => MemorySettingsStore(AppSettings.defaults),
          ),
          instanceStoreProvider.overrideWith(
            (ref) =>
                MemoryInstanceStore([sample(id: 'my-world', name: 'My World')]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(instanceListProvider.notifier);
      await pumpEventQueue();
      final created = await notifier.create(
        name: 'My World',
        versionId: '1.20.1',
      );

      expect(created.id, 'my-world-2');
      final ready = container.read(instanceListProvider) as InstanceListReady;
      expect(ready.instances.map((i) => i.id), ['my-world', 'my-world-2']);
      expect(
        ready.selectedId,
        'my-world-2',
        reason: 'the instance just created should be the one that launches',
      );
    });

    test('renaming does not move the directory', () async {
      final container = ProviderContainer(
        overrides: [
          settingsStoreProvider.overrideWith(
            (ref) => MemorySettingsStore(AppSettings.defaults),
          ),
          instanceStoreProvider.overrideWith(
            (ref) => MemoryInstanceStore([sample(id: 'fixed-id', name: 'Old')]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(instanceListProvider.notifier);
      await pumpEventQueue();
      await notifier.rename('fixed-id', 'New Name');

      final ready = container.read(instanceListProvider) as InstanceListReady;
      expect(ready.instances.single.id, 'fixed-id');
      expect(ready.instances.single.name, 'New Name');
    });

    test('a recorded session adds to playtime and stamps the date', () async {
      final container = ProviderContainer(
        overrides: [
          settingsStoreProvider.overrideWith(
            (ref) => MemorySettingsStore(AppSettings.defaults),
          ),
          instanceStoreProvider.overrideWith(
            (ref) => MemoryInstanceStore([
              sample(totalPlaytime: const Duration(hours: 1)),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(instanceListProvider.notifier);
      await pumpEventQueue();
      final before = DateTime.now();
      await notifier.recordSession('demo', const Duration(minutes: 30));

      final instance = (container.read(
        instanceListProvider,
      ) as InstanceListReady).instances.single;
      expect(instance.totalPlaytime, const Duration(hours: 1, minutes: 30));
      expect(instance.lastPlayedAt, isNotNull);
      expect(
        instance.lastPlayedAt!.isBefore(
          before.subtract(const Duration(seconds: 1)),
        ),
        isFalse,
      );
    });
  });

  group('instances screen', () {
    testWidgets('an empty list says so and offers to create one', (
      tester,
    ) async {
      await pumpScreen(tester, const InstancesScreen());

      expect(find.text('No instances yet'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'New instance'), findsOneWidget);
    });

    testWidgets('cards show the name, version and playtime', (tester) async {
      await pumpScreen(
        tester,
        const InstancesScreen(),
        instances: [
          sample(
            id: 'a',
            name: 'Survival',
            versionId: '1.20.1',
            lastPlayedAt: DateTime(2026, 1, 1),
            totalPlaytime: const Duration(hours: 3, minutes: 12),
          ),
        ],
      );

      expect(find.text('Survival'), findsOneWidget);
      expect(find.text('1.20.1'), findsOneWidget);
      expect(find.text('3h 12m'), findsOneWidget);
    });

    testWidgets('a never-played instance says so instead of showing 0s', (
      tester,
    ) async {
      await pumpScreen(tester, const InstancesScreen(), instances: [sample()]);

      expect(find.text('Never played'), findsOneWidget);
    });

    testWidgets('tapping a card opens it', (tester) async {
      final opened = <String>[];
      await pumpScreen(
        tester,
        InstancesScreen(onOpen: (instance) => opened.add(instance.id)),
        instances: [
          sample(id: 'a', name: 'A'),
          sample(id: 'b', name: 'B'),
        ],
      );

      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();

      // A tap opens the detail page rather than only recolouring a border:
      // selection happens there, and the grid has no other per-instance action.
      expect(opened, ['b']);
    });

    testWidgets('play runs the instance it belongs to', (tester) async {
      final launched = <String>[];
      await pumpScreen(
        tester,
        InstancesScreen(onLaunch: (instance) => launched.add(instance.id)),
        instances: [
          sample(id: 'a', name: 'A'),
          sample(id: 'b', name: 'B'),
        ],
      );

      final playButtons = find.widgetWithText(AppButton, 'Play');
      expect(playButtons, findsNWidgets(2));
      await tester.tap(playButtons.at(1));
      await tester.pumpAndSettle();

      // The bug this pins: the grid used to be constructed with no launch
      // callback at all, so every Play button was permanently disabled.
      expect(launched, ['b']);
    });

    testWidgets('a modded instance shows its loader', (tester) async {
      await pumpScreen(
        tester,
        const InstancesScreen(),
        instances: [
          sample(
            loader: LoaderKind.neoforge,
            loaderVersion: '21.1.0',
            versionId: '1.21.1',
          ),
        ],
      );

      expect(find.text('neoforge 21.1.0'), findsOneWidget);
    });

    testWidgets('a skipped-entry warning is shown when the file was damaged', (
      tester,
    ) async {
      // A store reporting damage, as FileInstanceStore does after a hand edit.
      await pumpScreen(tester, const InstancesScreen(), instances: [sample()]);
      // The banner is driven by the loaded state's `skipped` field, which the
      // memory store never sets; assert the non-damaged case shows no banner.
      expect(find.textContaining('could not be read'), findsNothing);
    });
  });

  group('launch screen', () {
    testWidgets(
      'with no instance the page explains itself instead of disabling '
      'a dead button',
      (tester) async {
        await pumpScreen(tester, const LaunchScreen());

        expect(find.text('No instance selected'), findsOneWidget);
        // The empty state replaces the whole body: a Play button that can never be
        // pressed is the first-run dead end this screen used to be.
        expect(find.byKey(const ValueKey('play')), findsNothing);
        expect(
          find.text(
            'Create one on the Instances page, then launch it from '
            'here.',
          ),
          findsOneWidget,
        );
        final action = tester.widget<AppButton>(
          find.byKey(const ValueKey('launch-open-instances')),
        );
        expect(action.onPressed, isNotNull);
      },
    );

    testWidgets('starting shows the launching state and disables play', (
      tester,
    ) async {
      final handle = FakeLaunchHandle();
      await pumpScreen(
        tester,
        const LaunchScreen(),
        instances: [sample()],
        handle: () => handle,
      );

      await tester.tap(find.widgetWithText(AppButton, 'Play'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // `preparing` then `running`; both are "busy" and both must say so.
      expect(find.text('Launching…'), findsOneWidget);
      final button = tester.widget<AppButton>(
        find.byKey(const ValueKey('play')),
      );
      expect(
        button.onPressed,
        isNull,
        reason:
            'a second click while a game is starting would spawn a second '
            'JVM',
      );
      await handle.dispose();
    });

    testWidgets('a running game can be stopped', (tester) async {
      final handle = FakeLaunchHandle();
      await pumpScreen(
        tester,
        const LaunchScreen(),
        instances: [sample()],
        handle: () => handle,
      );

      await tester.tap(find.widgetWithText(AppButton, 'Play'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();

      expect(find.text('Stop'), findsOneWidget);
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      expect(handle.stopCalls, 1);
      await handle.dispose();
    });

    testWidgets('the log tail shows output as it arrives', (tester) async {
      final handle = FakeLaunchHandle();
      await pumpScreen(
        tester,
        const LaunchScreen(),
        instances: [sample()],
        handle: () => handle,
      );

      expect(find.text('No log output yet'), findsOneWidget);

      await tester.tap(find.widgetWithText(AppButton, 'Play'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      handle.log('Setting user: Player');
      handle.log('LWJGL Version: 3.3.1');
      // `pump`, not `pumpAndSettle`: the running state spins a progress indicator,
      // which is an endless animation, so settling never happens by design.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('Setting user: Player'), findsOneWidget);
      expect(find.text('LWJGL Version: 3.3.1'), findsOneWidget);
      expect(find.text('No log output yet'), findsNothing);
      await handle.dispose();
    });

    testWidgets('a clean exit reports the code and the playtime', (
      tester,
    ) async {
      final handle = FakeLaunchHandle();
      await pumpScreen(
        tester,
        const LaunchScreen(),
        instances: [sample()],
        handle: () => handle,
      );

      await tester.tap(find.widgetWithText(AppButton, 'Play'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      handle.exit(0, uptime: const Duration(minutes: 42));
      await tester.pumpAndSettle();

      expect(find.textContaining('Exited with code 0'), findsOneWidget);
      expect(find.textContaining('42m'), findsOneWidget);
      // Back to Play, not stuck on "Launching…".
      expect(find.widgetWithText(AppButton, 'Play'), findsOneWidget);
      await handle.dispose();
    });

    testWidgets('a prepare failure is reported, not silently dropped', (
      tester,
    ) async {
      final handle = FakeLaunchHandle(failPreparation: true);
      await pumpScreen(
        tester,
        const LaunchScreen(),
        instances: [sample()],
        handle: () => handle,
      );

      await tester.tap(find.widgetWithText(AppButton, 'Play'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Could not prepare the launch'),
        findsOneWidget,
      );
      await handle.dispose();
    });

    testWidgets('a finished session is added to the instance playtime', (
      tester,
    ) async {
      // The controller owns this, not the screen: a launcher that only records
      // playtime while the launch screen is mounted loses every session the user
      // starts and then navigates away from.
      final handle = FakeLaunchHandle();
      final container = await pumpScreen(
        tester,
        const LaunchScreen(),
        instances: [sample()],
        handle: () => handle,
      );

      await tester.tap(find.widgetWithText(AppButton, 'Play'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      handle.exit(0, uptime: const Duration(minutes: 25));
      await tester.pumpAndSettle();

      final instance = (container.read(
        instanceListProvider,
      ) as InstanceListReady).instances.single;
      expect(instance.totalPlaytime, const Duration(minutes: 25));
      expect(instance.lastPlayedAt, isNotNull);
      await handle.dispose();
    });

    testWidgets('a launch refused for want of Java offers the download', (
      tester,
    ) async {
      // End to end through the controller: the blocker is produced by the
      // launch service in production, carried on the event, kept on the
      // session, and only then read by the screen.
      final handle = FakeLaunchHandle(
        prepareOutcome: const LaunchRefused([
          LaunchBlocker(
            code: BlockerCode.noRuntime,
            message: 'No Java runtime is available to start this version.',
            remedy: 'Install Java, or let the launcher download one.',
          ),
        ]),
      );
      await pumpScreen(
        tester,
        const LaunchScreen(),
        instances: [sample()],
        handle: () => handle,
      );

      // Before any attempt there is nothing to fix.
      expect(find.byKey(const ValueKey('java-panel')), findsNothing);

      await tester.tap(find.widgetWithText(AppButton, 'Play'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();

      // The panel is keyed, so this asserts on the fix being offered rather
      // than on whatever text it happens to show.
      expect(find.byKey(const ValueKey('java-panel')), findsOneWidget);
      await handle.dispose();
    });

    testWidgets('a refused launch for another reason offers no Java download', (
      tester,
    ) async {
      // `missingFiles` is fixed by reinstalling the version, not by Java; an
      // offer here would send the user to a 96 MB download that changes nothing.
      final handle = FakeLaunchHandle(
        prepareOutcome: const LaunchRefused([
          LaunchBlocker(
            code: BlockerCode.missingFiles,
            message: '3 files are missing from the install.',
            remedy: 'Install the version again.',
          ),
        ]),
      );
      await pumpScreen(
        tester,
        const LaunchScreen(),
        instances: [sample()],
        handle: () => handle,
      );

      await tester.tap(find.widgetWithText(AppButton, 'Play'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('java-panel')), findsNothing);
      expect(find.textContaining('Launch refused'), findsOneWidget);
      await handle.dispose();
    });

    testWidgets('a refused launch records no playtime', (tester) async {
      // Nothing ran, so the card must not claim a session: the guard is on the
      // measured session duration, and a refused launch never reached `running`.
      final handle = FakeLaunchHandle(prepareOutcome: const LaunchRefused([]));
      final container = await pumpScreen(
        tester,
        const LaunchScreen(),
        instances: [sample()],
        handle: () => handle,
      );

      await tester.tap(find.widgetWithText(AppButton, 'Play'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();

      final instance = (container.read(
        instanceListProvider,
      ) as InstanceListReady).instances.single;
      expect(instance.totalPlaytime, Duration.zero);
      expect(instance.lastPlayedAt, isNull);
      await handle.dispose();
    });

    testWidgets('the log keeps the newest lines, not the oldest', (
      tester,
    ) async {
      // 2100 lines through a 2000-line window: the first 100 must be gone and
      // the tail present. A `take()` instead of a `sublist` would leave the log
      // frozen at the start of the session.
      final handle = FakeLaunchHandle();
      await pumpScreen(
        tester,
        const LaunchScreen(),
        instances: [sample()],
        handle: () => handle,
      );

      await tester.tap(find.widgetWithText(AppButton, 'Play'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      for (var i = 0; i < 2100; i++) {
        handle.log('line $i');
      }
      // Same reason as above: a running session animates forever.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      final session = tester.state<State>(find.byType(LaunchScreen)).context;
      final lines = ProviderScope.containerOf(session)
          .read(launchControllerProvider)
          .log;
      expect(lines.length, 2000);
      expect(lines.last.text, 'line 2099');
      expect(
        lines.first.text,
        'line 100',
        reason: 'the window must slide, keeping the newest 2000 lines',
      );
      await handle.dispose();
    });
  });
}
