import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/server/server_ping.dart';

/// How the launcher asks a server whether it is up.
///
/// A provider rather than a direct call so a widget test can answer without a socket:
/// the ping lives behind a real connection, and a test that opens one is a test that
/// fails on a machine without a network.
final serverPingerProvider =
    Provider<Future<ServerPing> Function(String address)>((ref) {
      const ping = ServerListPing();
      return (address) => ping.ping(address);
    });

/// The ping for one address, cached per address and dropped when the list is refreshed.
///
/// `autoDispose` on purpose: a server list that was closed should not keep a status
/// forever, and a user who reopens the page wants a fresh answer, not this morning's.
final serverPingProvider = FutureProvider.autoDispose
    .family<ServerPing, String>(
      (ref, address) => ref.watch(serverPingerProvider)(address),
    );
