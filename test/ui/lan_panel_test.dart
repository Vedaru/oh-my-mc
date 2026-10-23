import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/app/providers.dart';
import 'package:oh_my_mc/core/diagnostics/lan_discovery.dart';
import 'package:oh_my_mc/core/diagnostics/network_info.dart';
import 'package:oh_my_mc/core/diagnostics/speed_test.dart';
import 'package:oh_my_mc/core/diagnostics/upnp.dart';
import 'package:oh_my_mc/data/diagnostics_providers.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:oh_my_mc/ui/network/lan_panel.dart';

import '../support/harness.dart';

/// 联机's two halves are both "ask the network something and show the answer". The
/// sockets are faked; what is pinned is that the *port from the announcement* is the
/// one that gets mapped, and that nothing is claimed when there is no gateway.
class _FakeDiscovery implements LanDiscovery {
  _FakeDiscovery(this.worlds);

  final List<LanWorld> worlds;

  @override
  Future<List<LanWorld>> discover({
    Future<List<LanWorld>> Function(Duration window)? listener,
  }) async => worlds;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUpnp implements UpnpClient {
  _FakeUpnp({this.gateway, this.external = '203.0.113.7'});

  final bool? gateway;
  final String? external;
  final mapped = <int>[];
  final unmapped = <int>[];

  UpnpGateway get _gateway => UpnpGateway(
    friendlyName: 'Test Router',
    controlUrl: Uri.parse('http://127.0.0.1:1/control'),
    serviceType: 'urn:schemas-upnp-org:service:WANIPConnection:1',
    localAddress: '192.168.1.23',
  );

  @override
  Future<UpnpGateway?> discover({String? localAddress}) async =>
      gateway == false ? null : _gateway;

  @override
  Future<PortMapping?> mapPort({
    required UpnpGateway gateway,
    required int internalPort,
    int? externalPort,
    String description = 'oh-my-mc',
    Duration lease = const Duration(hours: 2),
  }) async {
    mapped.add(internalPort);
    return PortMapping(
      externalPort: externalPort ?? internalPort,
      internalPort: internalPort,
      externalAddress: external,
    );
  }

  @override
  Future<bool> unmapPort({
    required UpnpGateway gateway,
    required int externalPort,
  }) async {
    unmapped.add(externalPort);
    return true;
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> pump(
    WidgetTester tester, {
    List<LanWorld> worlds = const [],
    _FakeUpnp? upnp,
  }) async {
    final container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWith(
          (ref) => MemorySettingsStore(AppSettings.defaults),
        ),
        lanInterfacesProvider.overrideWith(
          (ref) async => const [
            LanInterface(name: 'wlan0', ipv4: ['192.168.1.23']),
          ],
        ),
        speedTestProvider.overrideWithValue(SpeedTest()),
        lanDiscoveryProvider.overrideWithValue(_FakeDiscovery(worlds)),
        upnpClientProvider.overrideWithValue(upnp ?? _FakeUpnp()),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpScreen(tester, container, const LanPanel());
    await tester.pumpAndSettle();
  }

  testWidgets('a scan lists what the network announced', (tester) async {
    await pump(
      tester,
      worlds: const [
        LanWorld(motd: 'Survival', port: 54321, address: '192.168.1.9'),
      ],
    );

    await tester.tap(find.byKey(const m3.ValueKey('lan-scan')));
    await tester.pumpAndSettle();

    expect(find.text('Survival'), findsOneWidget);
    // The address a friend on the LAN types, port included.
    expect(find.text('192.168.1.9:54321'), findsOneWidget);
  });

  testWidgets('an empty scan says so, but only after scanning', (tester) async {
    await pump(tester);

    expect(find.textContaining('Nothing announced'), findsNothing);

    await tester.tap(find.byKey(const m3.ValueKey('lan-scan')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Nothing announced'), findsOneWidget);
  });

  testWidgets('opening the port maps the port the game announced', (
    tester,
  ) async {
    final upnp = _FakeUpnp();
    await pump(
      tester,
      worlds: const [
        LanWorld(motd: 'Survival', port: 54321, address: '192.168.1.9'),
      ],
      upnp: upnp,
    );
    await tester.tap(find.byKey(const m3.ValueKey('lan-scan')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open port'));
    await tester.pumpAndSettle();

    // Not a port from settings: the one the announcement carried.
    expect(upnp.mapped, [54321]);
    expect(find.text('203.0.113.7:54321'), findsOneWidget);
  });

  testWidgets('closing the port removes exactly that mapping', (tester) async {
    final upnp = _FakeUpnp();
    await pump(
      tester,
      worlds: const [
        LanWorld(motd: 'Survival', port: 54321, address: '192.168.1.9'),
      ],
      upnp: upnp,
    );
    await tester.tap(find.byKey(const m3.ValueKey('lan-scan')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open port'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Close port'));
    await tester.pumpAndSettle();

    expect(upnp.unmapped, [54321]);
    expect(find.byKey(const m3.ValueKey('lan-mapping')), findsNothing);
  });

  testWidgets('with no gateway the panel claims nothing', (tester) async {
    await pump(
      tester,
      worlds: const [
        LanWorld(motd: 'Survival', port: 54321, address: '192.168.1.9'),
      ],
      upnp: _FakeUpnp(gateway: false),
    );
    await tester.tap(find.byKey(const m3.ValueKey('lan-scan')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open port'));
    await tester.pumpAndSettle();

    // No mapping row and no invented address: the router said nothing, so neither
    // does the launcher.
    expect(find.byKey(const m3.ValueKey('lan-mapping')), findsNothing);
  });

  testWidgets(
    'a gateway without an external address says so instead of guessing',
    (tester) async {
      await pump(
        tester,
        worlds: const [
          LanWorld(motd: 'Survival', port: 54321, address: '192.168.1.9'),
        ],
        upnp: _FakeUpnp(external: null),
      );
      await tester.tap(find.byKey(const m3.ValueKey('lan-scan')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open port'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('did not report an external address'),
        findsOneWidget,
      );
    },
  );
}
