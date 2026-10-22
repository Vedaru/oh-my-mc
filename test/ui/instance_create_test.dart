import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/app/providers.dart';
import 'package:oh_my_mc/data/install_providers.dart';
import 'package:oh_my_mc/data/instance_providers.dart';
import 'package:oh_my_mc/data/instance_store.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:oh_my_mc/ui/instances/instances_screen.dart';

import '../support/harness.dart';

/// A fixed "installed versions" set: the real provider lists the filesystem, which
/// a widget test has no business touching.
class _Installed extends InstalledVersions {
  _Installed(this.versions);

  final Set<String> versions;

  @override
  Set<String> build() => versions;
}

Future<ProviderContainer> _container(
  WidgetTester tester, {
  Set<String> installed = const {'1.20.1', '26.3'},
}) async {
  final container = ProviderContainer(
    overrides: [
      instanceStoreProvider.overrideWith(
        (ref) => MemoryInstanceStore(const []),
      ),
      installedVersionsProvider.overrideWith(() => _Installed(installed)),
      settingsStoreProvider.overrideWith((ref) => MemorySettingsStore()),
    ],
  );
  addTearDown(container.dispose);
  await pumpScreen(tester, container, const InstancesScreen());
  return container;
}

void main() {
  group('versionsForPicker', () {
    test('newest-looking version first, numbers compared as numbers', () {
      expect(versionsForPicker({'1.20.1', '26.3', '1.9', '1.20.10'}), [
        '26.3',
        '1.20.10',
        '1.20.1',
        '1.9',
      ]);
    });
  });

  group('creating an instance', () {
    testWidgets('the version is chosen, not hardcoded', (tester) async {
      final container = await _container(tester);

      await tester.tap(find.text('New instance').first);
      await tester.pumpAndSettle();

      // The dialog offers the installed versions, with the newest preselected.
      final dropdown = find.byKey(const ValueKey('instance-version'));
      expect(dropdown, findsOneWidget);
      expect(find.text('26.3'), findsWidgets);

      // Pick the older one explicitly, so the test proves the choice is carried.
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('1.20.1').last);
      await tester.pumpAndSettle();

      // By key: the dropdown contains a TextField of its own, so `byType` is
      // ambiguous here.
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('instance-name')),
          matching: find.byType(m3.TextField),
        ),
        'Vanilla 1.20.1',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('instance-create-confirm')));
      await tester.pumpAndSettle();

      final created = container.read(instanceListProvider) as InstanceListReady;
      expect(created.instances.single.name, 'Vanilla 1.20.1');
      expect(created.instances.single.versionId, '1.20.1');
    });

    testWidgets('with no version installed it points at the download page', (
      tester,
    ) async {
      await _container(tester, installed: const {});

      await tester.tap(find.text('New instance').first);
      await tester.pumpAndSettle();

      expect(find.text('No game version is installed yet'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('instance-create-download')),
        findsOneWidget,
      );
      // No half-created instance bound to a version that is not on disk.
      expect(
        find.byKey(const ValueKey('instance-create-confirm')),
        findsNothing,
      );
    });
  });
}
