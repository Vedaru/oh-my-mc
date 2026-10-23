import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/diagnostics/lan_discovery.dart';
import '../core/diagnostics/network_info.dart';
import '../core/diagnostics/speed_test.dart';
import '../core/diagnostics/upnp.dart';

/// The machine's interfaces, behind a provider so a test can answer without
/// touching the real network stack.
final lanInterfacesProvider = FutureProvider<List<LanInterface>>(
  (ref) => lanInterfaces(),
);

/// The speed test is a service, not state: the panel owns the run and the results.
final speedTestProvider = Provider<SpeedTest>((ref) {
  final test = SpeedTest();
  ref.onDispose(test.close);
  return test;
});

/// Finds worlds the host machine has opened to LAN.
///
/// A provider so a test can answer with worlds it made up: the real one binds a
/// multicast socket and waits three seconds, which no widget test should do.
final lanDiscoveryProvider = Provider<LanDiscovery>(
  (ref) => const LanDiscovery(),
);

/// The UPnP client, for opening the port a LAN world listens on.
final upnpClientProvider = Provider<UpnpClient>((ref) {
  final client = UpnpClient();
  ref.onDispose(client.close);
  return client;
});
