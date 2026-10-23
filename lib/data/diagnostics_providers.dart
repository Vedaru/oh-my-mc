import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/diagnostics/network_info.dart';
import '../core/diagnostics/speed_test.dart';

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
