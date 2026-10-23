import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/core/diagnostics/crash_analyzer.dart';
import 'package:oh_my_mc/core/diagnostics/network_info.dart';
import 'package:oh_my_mc/core/diagnostics/speed_test.dart';
import 'package:oh_my_mc/data/diagnostics_providers.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:oh_my_mc/app/providers.dart';
import 'package:oh_my_mc/l10n/l10n.dart';
import 'package:oh_my_mc/l10n/generated/app_localizations.dart';
import 'package:oh_my_mc/ui/launch/crash_card.dart';
import 'package:oh_my_mc/ui/launch/crash_copy.dart';
import 'package:oh_my_mc/ui/setup/network_panel.dart';

import '../support/harness.dart';

/// A speed test that answers from a script, so the panel's job - showing results as
/// they arrive and staying quiet about failures - is testable.
class _ScriptedSpeedTest extends SpeedTest {
  _ScriptedSpeedTest(this.samples);

  final List<SpeedSample> samples;
  var runs = 0;

  @override
  Future<List<SpeedSample>> run(
    List<Mirror> mirrors, {
    void Function(SpeedSample sample)? onSample,
  }) async {
    runs++;
    for (final sample in samples) {
      onSample?.call(sample);
    }
    return samples;
  }
}

void main() {
  group('network panel', () {
    Future<void> pump(
      WidgetTester tester, {
      List<LanInterface> interfaces = const [],
      List<SpeedSample> samples = const [],
    }) async {
      final test = _ScriptedSpeedTest(samples);
      final container = ProviderContainer(
        overrides: [
          // The panel also shows the download-source preference, which reads settings.
          settingsStoreProvider.overrideWith(
            (ref) => MemorySettingsStore(AppSettings.defaults),
          ),
          lanInterfacesProvider.overrideWith((ref) async => interfaces),
          speedTestProvider.overrideWithValue(test),
        ],
      );
      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpScreen(tester, container, const NetworkPanel());
      await tester.pumpAndSettle();
    }

    testWidgets('shows the address to share, with its interface', (
      tester,
    ) async {
      await pump(
        tester,
        interfaces: const [
          LanInterface(name: 'docker0', ipv4: ['172.17.0.1']),
          LanInterface(name: 'wlan0', ipv4: ['192.168.1.23']),
        ],
      );

      // The tunnel is not offered: a friend cannot reach it.
      expect(find.textContaining('192.168.1.23'), findsOneWidget);
      expect(find.textContaining('172.17.0.1'), findsNothing);
      expect(find.textContaining('wlan0'), findsOneWidget);
    });

    testWidgets('no interface reads as a sentence, not an empty row', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('No network interface found'), findsOneWidget);
      // Nothing to copy, so no button that would copy nothing.
      expect(find.byKey(const m3.ValueKey('lan-copy')), findsNothing);
    });

    testWidgets('the speed test lists each mirror as it finishes', (
      tester,
    ) async {
      await pump(
        tester,
        samples: const [
          SpeedSample(
            name: 'Mojang',
            url: 'https://example/mojang.jar',
            bytes: 2 * 1024 * 1024,
            elapsed: Duration(milliseconds: 500),
          ),
          SpeedSample(
            name: 'Modrinth',
            url: 'https://example/sodium.jar',
            error: 'HTTP 404',
          ),
        ],
      );

      await tester.tap(find.byKey(const m3.ValueKey('speed-test')));
      await tester.pumpAndSettle();

      // "Mojang" is also a radio label below, so the row is found by key.
      expect(find.byKey(const m3.ValueKey('speed-Mojang')), findsOneWidget);
      expect(find.text('4.0 MB/s'), findsOneWidget);
      // The failure keeps its reason instead of showing a fake number.
      expect(find.text('HTTP 404'), findsOneWidget);
    });
  });

  group('crash card', () {
    testWidgets('an OOM crash offers memory, not a stack trace', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await pumpScreen(
        tester,
        container,
        CrashCard(
          diagnosis: CrashAnalyzer.analyze([
            'java.lang.OutOfMemoryError: Java heap space',
          ], exitCode: 1)!,
          instanceId: 'a',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Out of memory'), findsOneWidget);
      expect(find.textContaining('4 GB'), findsOneWidget);
      expect(
        find.byKey(const m3.ValueKey('crash-action-raiseMemory')),
        findsOneWidget,
      );
      // The evidence is there to copy, not to read first.
      expect(find.textContaining('Java heap space'), findsOneWidget);
    });

    testWidgets('retry is only offered when it can do something', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final diagnosis = CrashAnalyzer.analyze([
        'java.net.UnknownHostException: files.minecraftforge.net',
      ], exitCode: 1)!;

      await pumpScreen(
        tester,
        container,
        CrashCard(diagnosis: diagnosis, instanceId: 'a'),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const m3.ValueKey('crash-action-retry')),
        findsNothing,
        reason: 'a retry button with no callback is a button that lies',
      );
    });

    testWidgets('a retry callback produces the button', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final diagnosis = CrashAnalyzer.analyze([
        'java.net.UnknownHostException: example.invalid',
      ], exitCode: 1)!;

      await pumpScreen(
        tester,
        container,
        CrashCard(diagnosis: diagnosis, instanceId: 'a', onRetry: () {}),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const m3.ValueKey('crash-action-retry')),
        findsOneWidget,
      );
    });
  });

  group('crash copy', () {
    Diagnosis oom() => CrashAnalyzer.analyze([
      'java.lang.OutOfMemoryError: Java heap space',
    ], exitCode: 1)!;

    test('the sentence follows the UI language', () {
      final en = CrashCopy.of(
        oom(),
        lookupAppLocalizations(const Locale('en')),
      );
      final zh = CrashCopy.of(
        oom(),
        lookupAppLocalizations(const Locale('zh')),
      );

      expect(en.title, 'Out of memory');
      expect(zh.title, '内存不足');
      // Neither language embeds a label from the other: that was the bug when the
      // analyzer owned this text.
      expect(zh.body, isNot(contains('version settings')));
      expect(en.body, isNot(contains('版本设置')));
    });

    test('the Java version is named when it is known', () {
      final diagnosis = CrashAnalyzer.analyze([
        'java.lang.UnsupportedClassVersionError: Main has been compiled by a more '
            'recent version of the Java Runtime (class file version 61.0)',
      ], exitCode: 1)!;

      final copy = CrashCopy.of(
        diagnosis,
        lookupAppLocalizations(const Locale('en')),
      );

      expect(copy.title, 'This version needs Java 17');
      expect(copy.body, contains('Java 17'));
    });

    test('the exit code is named when nothing else is known', () {
      final diagnosis = CrashAnalyzer.analyze(const [], exitCode: 1)!;

      final copy = CrashCopy.of(
        diagnosis,
        lookupAppLocalizations(const Locale('en')),
      );

      expect(copy.title, contains('1'));
    });
  });
}
