import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/server/server_ping.dart';

/// A real socket that speaks the two ping protocols, so the test exercises the bytes
/// this launcher sends instead of a re-implementation of them.
class _FakeServer {
  late final ServerSocket _socket;
  final connects = <String>[];

  static Future<_FakeServer> start({required bool modern, String? motd}) async {
    final server = _FakeServer();
    server._socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server._socket.listen((client) async {
      final bytes = <int>[];
      client.listen((chunk) {
        bytes.addAll(chunk);
        if (modern) {
          // A status request is a 2-byte packet: length 1, id 0. Once it is here the
          // handshake has been consumed and it is time to answer.
          if (bytes.length >= 2 && bytes[bytes.length - 1] == 0x00) {
            _FakeServer._answerModern(client, motd ?? 'A §9Fake §lServer');
          }
        } else if (bytes.length >= 2) {
          client.add(_legacyAnswer(motd ?? 'Old Server', online: 2, max: 8));
        }
      });
    });
    return server;
  }

  int get port => _socket.port;

  static void _answerModern(Socket client, String motd) {
    final json = jsonEncode({
      'version': {'name': '1.20.1', 'protocol': 763},
      'players': {'online': 7, 'max': 20},
      'description': {'text': motd},
    });
    final payload = <int>[
      0x00,
      // string: varint length then utf8
      ..._varInt(utf8.encode(json).length),
      ...utf8.encode(json),
    ];
    client.add(<int>[..._varInt(payload.length), ...payload]);
  }

  static List<int> _legacyAnswer(
    String motd, {
    required int online,
    required int max,
  }) {
    // The real pre-1.7 payload: §1, protocol, MOTD, online, max - UTF-16BE, NUL
    // separated.
    final text = '\u00a71\u0000127\u0000$motd\u0000$online\u0000$max';
    final utf16 = <int>[];
    for (final unit in text.codeUnits) {
      utf16
        ..add((unit >> 8) & 0xFF)
        ..add(unit & 0xFF);
    }
    final length = utf16.length;
    return <int>[0xFF, (length >> 8) & 0xFF, length & 0xFF, ...utf16];
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

  Future<void> close() async => _socket.close();
}

void main() {
  test('addresses split the way servers.dat stores them', () {
    expect(ServerListPing.splitAddress('mc.example.net'), (
      'mc.example.net',
      25565,
    ));
    expect(ServerListPing.splitAddress('mc.example.net:25566'), (
      'mc.example.net',
      25566,
    ));
    // IPv6 keeps its brackets: the colon inside them is not a port separator.
    expect(ServerListPing.splitAddress('[::1]:25567'), ('[::1]', 25567));
    expect(ServerListPing.splitAddress('[::1]'), ('[::1]', 25565));
    expect(ServerListPing.splitAddress('mc.example.net', fallback: 19132), (
      'mc.example.net',
      19132,
    ));
  });

  test('a 1.7+ server answers with MOTD, players and latency', () async {
    final server = await _FakeServer.start(modern: true);
    addTearDown(server.close);

    final result = await ServerListPing().ping('127.0.0.1:${server.port}');

    expect(result.isOk, isTrue, reason: result.error);
    final status = result.status!;
    // The colour codes are gone: this launcher cannot render `§9`, and a raw code in a
    // row reads as a typo.
    expect(status.motd, 'A Fake Server');
    expect(status.online, 7);
    expect(status.max, 20);
    expect(status.players, '7/20');
    expect(status.version, '1.20.1');
    expect(status.latencyMs, isNotNull);
  });

  test('a pre-1.7 server is not reported as offline', () async {
    final server = await _FakeServer.start(modern: false, motd: 'Beta Box');
    addTearDown(server.close);

    final result = await ServerListPing().ping('127.0.0.1:${server.port}');

    expect(result.isOk, isTrue, reason: result.error);
    expect(result.status!.motd, 'Beta Box');
    expect(result.status!.players, '2/8');
  });

  test('a closed port is a failure with a reason, not an exception', () async {
    // Bind and close: the port is almost certainly free afterwards.
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();

    final result = await ServerListPing(
      timeout: const Duration(milliseconds: 500),
    ).ping('127.0.0.1:$port');

    expect(result.isOk, isFalse);
    expect(result.error, isNotEmpty);
  });

  test('a silent server times out instead of hanging the list', () async {
    // Accepts the connection and never answers - what a filtered port looks like.
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final held = <Socket>[];
    server.listen(held.add);

    final stopwatch = Stopwatch()..start();
    final result = await ServerListPing(
      timeout: const Duration(milliseconds: 300),
    ).ping('127.0.0.1:${server.port}');
    stopwatch.stop();

    expect(result.isOk, isFalse);
    // Modern attempt times out, then the legacy attempt times out again; two 300 ms
    // waits is the worst case, and it must stay bounded.
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
    for (final socket in held) {
      socket.destroy();
    }
  });
}
