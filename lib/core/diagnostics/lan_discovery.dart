import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A world another machine on the LAN has announced as open to LAN.
class LanWorld {
  const LanWorld({
    required this.motd,
    required this.port,
    required this.address,
  });

  /// The message of the day the host set, usually the world name.
  final String motd;

  /// The port the game opened. Random per session - this is the number the port
  /// mapping and the friend both need.
  final int port;

  /// Where the announcement came from.
  final String address;

  /// `192.168.1.9:54321`, which is what a friend types.
  String get shareAddress => '$address:$port';
}

/// Parses one announcement datagram.
///
/// Minecraft's format is `[MOTD]text[/MOTD][AD]port[/AD]`, and mods add keys after
/// it, so the parser extracts the two tags it needs and ignores the rest rather than
/// matching the whole string.
class LanAnnouncement {
  const LanAnnouncement({required this.motd, required this.port});

  final String motd;
  final int port;

  static LanAnnouncement? parse(String text) {
    final motd = RegExp(
      r'\[MOTD\](.*?)\[/MOTD\]',
      dotAll: true,
    ).firstMatch(text);
    final port = RegExp(r'\[AD\](\d+)\[/AD\]').firstMatch(text);
    if (motd == null || port == null) return null;
    final value = int.tryParse(port.group(1)!);
    if (value == null || value <= 0 || value > 65535) return null;
    return LanAnnouncement(motd: motd.group(1) ?? '', port: value);
  }
}

/// Listens for the game's LAN broadcasts.
///
/// The game multicasts `[MOTD]…[/MOTD][AD]port[/AD]` to 224.0.2.60:4445 every 1.5 s.
/// It is the only reliable way to learn two things the launcher cannot otherwise
/// know: that a world is open, and *which port* it opened - the game picks a random
/// one, so a port mapping without this is a guess.
class LanDiscovery {
  const LanDiscovery({
    this.group = '224.0.2.60',
    this.port = 4445,
    this.window = const Duration(seconds: 3),
  });

  final String group;
  final int port;

  /// How long to listen. Two announcement intervals, so a world that started a
  /// second ago is still caught.
  final Duration window;

  Future<List<LanWorld>> discover({
    Future<List<LanWorld>> Function(Duration window)? listener,
  }) async {
    if (listener != null) return listener(window);
    return _listen();
  }

  Future<List<LanWorld>> _listen() async {
    final found = <String, LanWorld>{};
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
      // Multi-homed machines need this on every interface that has a route to the
      // LAN; the game does the same.
      for (final interface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      )) {
        for (final _ in interface.addresses) {
          try {
            socket.joinMulticast(InternetAddress(group), interface);
          } on Object {
            // An interface that cannot join (a VPN, a down link) must not stop the
            // others from listening.
          }
        }
      }

      final done = Completer<void>();
      final subscription = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket?.receive();
        if (datagram == null) return;
        final text = utf8.decode(datagram.data, allowMalformed: true);
        final announcement = LanAnnouncement.parse(text);
        if (announcement == null) return;
        final world = LanWorld(
          motd: announcement.motd,
          port: announcement.port,
          address: datagram.address.address,
        );
        found[world.shareAddress] = world;
      });
      // The window is time-based: worlds announce on their own schedule, so there is
      // no "done" event to wait for.
      Timer(window, () => done.complete());
      await done.future;
      await subscription.cancel();
    } on SocketException {
      return const [];
    } finally {
      socket?.close();
    }
    return found.values.toList();
  }
}
