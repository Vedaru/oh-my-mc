import '../server/server_ping.dart';

/// "Start the game and go straight to this server."
///
/// The multiplayer screen is a step the launcher can skip: the address is already in
/// `servers.dat`, so a join is two launch flags rather than something the user has to
/// type twice.
class JoinTarget {
  const JoinTarget({required this.host, required this.port});

  /// `mc.example.net:25565`, or a bare address with the default port.
  factory JoinTarget.parse(String address) {
    final (host, port) = ServerListPing.splitAddress(address);
    return JoinTarget(host: host, port: port);
  }

  final String host;
  final int port;

  /// The flags the game reads, oldest to newest aware.
  ///
  /// `--server` / `--port` still work on current versions and are the only pair that
  /// works on old ones; `--quickPlayMultiplayer` exists since 1.20 but conflicts with
  /// `--server` on some builds, so it is deliberately not sent.
  List<String> get gameArgs => ['--server', host, '--port', '$port'];

  @override
  String toString() => '$host:$port';
}
