import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// What a server answers when you ping it: the MOTD, the player counts, the version.
class ServerStatus {
  const ServerStatus({
    required this.motd,
    required this.online,
    required this.max,
    this.version,
    this.latencyMs,
  });

  /// The description line, with Minecraft's `§` colour codes removed: the launcher
  /// has no font that can render them, and a raw `§a` in a row is noise.
  final String motd;
  final int online;
  final int max;
  final String? version;

  /// Round trip of the ping, in milliseconds. Null when the answer came from the
  /// legacy handshake, which has no reliable timestamp.
  final int? latencyMs;

  /// `3/20` - the form every server list in every launcher shows.
  String get players => '$online/$max';
}

/// The result of pinging one address: either a status or the reason there is none.
class ServerPing {
  const ServerPing.ok(this.status) : error = null;
  const ServerPing.failed(this.error) : status = null;

  final ServerStatus? status;
  final String? error;

  bool get isOk => status != null;
}

/// Server List Ping, the protocol behind the multiplayer screen.
///
/// A server row that never says whether the server is up is a row that only holds a
/// string. This speaks the two versions that matter:
///
/// * **1.7+**: a handshake packet with `next state = 1`, a status request, and the
///   JSON the server sends back;
/// * **pre-1.7**: a `0xFE` byte, and the `motd§online§max` string the old servers
///   answer with. Beta and 1.6 servers still exist, and a launcher that shows them as
///   "offline" is lying.
///
/// It never throws: a refused connection, a DNS failure and a timeout all come back as
/// [ServerPing.failed], because the caller draws them on a row.
class ServerListPing {
  const ServerListPing({this.timeout = const Duration(seconds: 4)});

  final Duration timeout;

  /// Ping `host:port`. `host` may already carry a port, which is the form
  /// `servers.dat` stores (`mc.example.net:25565`); `port` is the fallback.
  Future<ServerPing> ping(String address, {int port = 25565}) async {
    final (host, resolvedPort) = splitAddress(address, fallback: port);
    final stopwatch = Stopwatch()..start();
    try {
      final modern = await _modern(
        host,
        resolvedPort,
        stopwatch,
      ).timeout(timeout);
      if (modern != null) return ServerPing.ok(modern);
    } on Object {
      // Fall through: an old server drops the 1.7+ packet without answering.
    }
    try {
      final legacy = await _legacy(host, resolvedPort).timeout(timeout);
      if (legacy != null) return ServerPing.ok(legacy);
    } on Object catch (e) {
      return ServerPing.failed(_describe(e));
    }
    return const ServerPing.failed('no answer');
  }

  /// `host:port` → its parts. IPv6 literals keep their brackets.
  static (String, int) splitAddress(String address, {int fallback = 25565}) {
    final value = address.trim();
    if (value.startsWith('[')) {
      final end = value.indexOf(']');
      if (end > 0) {
        final host = value.substring(0, end + 1);
        final rest = value.substring(end + 1);
        if (rest.startsWith(':')) {
          final port = int.tryParse(rest.substring(1));
          if (port != null) return (host, port);
        }
        return (host, fallback);
      }
    }
    final colon = value.lastIndexOf(':');
    if (colon > 0 && !value.substring(colon + 1).contains(':')) {
      final port = int.tryParse(value.substring(colon + 1));
      if (port != null && port > 0 && port < 65536) {
        return (value.substring(0, colon), port);
      }
    }
    return (value, fallback);
  }

  Future<ServerStatus?> _modern(
    String host,
    int port,
    Stopwatch stopwatch,
  ) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    try {
      socket.add(_handshake(host, port));
      socket.add(_varIntPacket([0x00])); // status request
      await socket.flush();

      final reader = _PacketReader(socket);
      final length = await reader.varInt();
      if (length <= 0 || length > 1 << 20) return null;
      final packet = await reader.bytes(length);
      if (packet.isEmpty || packet.first != 0x00) return null;

      final payload = _readVarIntFrom(packet, 1);
      final json = jsonDecode(utf8.decode(payload));
      if (json is! Map) return null;

      stopwatch.stop();
      return ServerStatus(
        motd: _plainMotd(json['description']),
        online: _int(json['players']?['online']),
        max: _int(json['players']?['max']),
        version: json['version']?['name'] as String?,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } finally {
      socket.destroy();
    }
  }

  /// Pre-1.7: `0xFE 0x01`, and the server answers with a `0xFF` packet whose payload
  /// is UTF-16BE: `§1\0<protocol>\0<motd>\0<online>\0<max>`.
  ///
  /// Read exactly the declared length rather than waiting for the socket to close: an
  /// old server keeps the connection open, and "wait for end of stream" is how a ping
  /// turns into a timeout.
  Future<ServerStatus?> _legacy(String host, int port) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    try {
      socket.add(<int>[0xFE, 0x01]);
      await socket.flush();

      final bytes = <int>[];
      await for (final chunk in socket.timeout(timeout)) {
        bytes.addAll(chunk);
        if (bytes.length >= 3) {
          final declared = (bytes[1] << 8) | bytes[2];
          if (bytes.length >= 3 + declared) break;
        }
        if (bytes.length > 8192) break;
      }
      if (bytes.isEmpty || bytes.first != 0xFF || bytes.length < 3) return null;

      final declared = (bytes[1] << 8) | bytes[2];
      final payload = bytes.sublist(3, (3 + declared).clamp(0, bytes.length));
      final text = _utf16be(payload);
      final parts = text.split('\u0000');
      if (parts.length < 5) return null;
      return ServerStatus(
        motd: _stripCodes(parts[2]).trim(),
        online: int.tryParse(parts[3].trim()) ?? 0,
        max: int.tryParse(parts[4].trim()) ?? 0,
      );
    } finally {
      socket.destroy();
    }
  }

  /// UTF-16BE, the encoding the legacy ping uses for its payload.
  static String _utf16be(List<int> bytes) {
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      units.add((bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(units);
  }

  static Uint8List _handshake(String host, int port) {
    final payload = <int>[
      0x00,
      ..._varInt(-1 & 0x7FFFFFFF).map((b) => b), // protocol -1: "just asking"
      ..._string(host),
      (port >> 8) & 0xFF,
      port & 0xFF,
      0x01,
    ];
    return _varIntPacket(payload);
  }

  static Uint8List _varIntPacket(List<int> payload) {
    final body = <int>[..._varInt(payload.length), ...payload];
    return Uint8List.fromList(body);
  }

  static List<int> _varInt(int value) {
    final out = <int>[];
    var remaining = value;
    do {
      var byte = remaining & 0x7F;
      remaining >>= 7;
      if (remaining != 0) byte |= 0x80;
      out.add(byte);
    } while (remaining != 0);
    return out;
  }

  static List<int> _string(String value) {
    final bytes = utf8.encode(value);
    return [..._varInt(bytes.length), ...bytes];
  }

  /// The JSON payload of a status packet: a varint length, then the bytes.
  static List<int> _readVarIntFrom(List<int> bytes, int offset) {
    var length = 0;
    var shift = 0;
    var index = offset;
    while (index < bytes.length) {
      final byte = bytes[index++];
      length |= (byte & 0x7F) << shift;
      if (byte & 0x80 == 0) break;
      shift += 7;
      if (shift > 28) break;
    }
    if (index >= bytes.length) return const [];
    final end = index + length;
    return bytes.sublist(index, end > bytes.length ? bytes.length : end);
  }

  static int _int(Object? value) => value is int ? value : 0;

  /// The description is either a string or a chat component tree; both end up as
  /// plain text, without `§` codes.
  static String _plainMotd(Object? description) {
    if (description == null) return '';
    if (description is String) return _stripCodes(description);
    if (description is Map) {
      final buffer = StringBuffer();
      void visit(Object? node) {
        if (node is String) {
          buffer.write(_stripCodes(node));
        } else if (node is List) {
          node.forEach(visit);
        } else if (node is Map) {
          final text = node['text'];
          if (text is String) buffer.write(_stripCodes(text));
          visit(node['extra']);
        }
      }

      visit(description);
      return buffer.toString().trim();
    }
    return '';
  }

  /// Drops `§` colour codes: `§a` is two characters, and a font without the glyph
  /// draws a box.
  static String _stripCodes(String text) =>
      text.replaceAll(RegExp('\u00a7.'), '').trim();

  static String _describe(Object error) => switch (error) {
    SocketException(:final osError) => osError?.message ?? 'connection failed',
    TimeoutException() => 'timed out',
    _ => '$error',
  };
}

/// Reads length-prefixed packets off a socket.
class _PacketReader {
  _PacketReader(Socket socket) {
    _subscription = socket.listen(
      (chunk) {
        _buffer.addAll(chunk);
        _wake();
      },
      onError: (Object error) {
        _error = error;
        _wake();
      },
      onDone: () {
        _done = true;
        _wake();
      },
    );
  }

  final _buffer = <int>[];
  late final StreamSubscription<Uint8List> _subscription;
  Object? _error;
  var _done = false;
  Completer<void>? _waiting;

  void _wake() {
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
  }

  Future<void> _fill(int needed) async {
    while (_buffer.length < needed) {
      if (_error != null) throw _error!;
      if (_done) throw const SocketException('connection closed');
      _waiting = Completer<void>();
      await _waiting!.future;
    }
  }

  Future<int> varInt() async {
    var result = 0;
    var shift = 0;
    while (shift <= 28) {
      await _fill(1);
      final byte = _buffer.removeAt(0);
      result |= (byte & 0x7F) << shift;
      if (byte & 0x80 == 0) return result;
      shift += 7;
    }
    throw const FormatException('varint too long');
  }

  Future<List<int>> bytes(int length) async {
    await _fill(length);
    final out = _buffer.sublist(0, length);
    _buffer.removeRange(0, length);
    return out;
  }

  Future<void> close() => _subscription.cancel();
}
