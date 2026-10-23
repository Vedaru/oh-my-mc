import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/diagnostics/network_info.dart';
import 'package:oh_my_mc/core/diagnostics/speed_test.dart';

/// A local server that serves `size` bytes of a given chunk pattern, so throughput
/// is measurable without the internet.
class _Server {
  _Server._(this._server, this.bytes);

  final HttpServer _server;
  final int bytes;
  var requests = 0;

  static Future<_Server> start({int bytes = 512 * 1024}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _Server._(server, bytes);
    server.listen((request) async {
      fake.requests++;
      if (request.uri.path == '/missing') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      if (request.uri.path == '/slow') {
        // Says it has a body and then never finishes: the timeout path.
        request.response.headers.contentLength = bytes;
        await request.response.flush();
        return;
      }
      request.response.headers.contentLength = bytes;
      final chunk = List<int>.filled(16 * 1024, 7);
      var sent = 0;
      while (sent < bytes) {
        request.response.add(chunk);
        sent += chunk.length;
      }
      await request.response.close();
    });
    return fake;
  }

  Uri url(String path) => Uri.parse('http://127.0.0.1:${_server.port}$path');
  Future<void> close() => _server.close(force: true);
}

void main() {
  group('speed test', () {
    late _Server server;

    // 8 MB, not 512 KB: on loopback a small body arrives as one chunk and a cap
    // below its size would never be reached.
    setUp(() async => server = await _Server.start(bytes: 8 * 1024 * 1024));
    tearDown(() async => server.close());

    test('measures bytes per second and stops at the cap', () async {
      final test = SpeedTest(maxBytes: 64 * 1024);
      final sample = await test.measure(
        Mirror('local', server.url('/file').toString()),
      );

      expect(sample.ok, isTrue);
      // The transfer is cut short: an 8 MB body does not arrive in full. The exact
      // stop point depends on socket buffering, so this asserts the behaviour that
      // matters (it stops) rather than a byte count.
      expect(sample.bytes, greaterThanOrEqualTo(64 * 1024));
      expect(sample.bytes, lessThan(8 * 1024 * 1024));
      expect(sample.bytesPerSecond, greaterThan(0));
      expect(sample.label, contains('MB/s'));
    });

    test('an unreachable mirror fails without breaking the run', () async {
      final test = SpeedTest();
      final samples = await test.run([
        Mirror('missing', server.url('/missing').toString()),
        Mirror('good', server.url('/file').toString()),
      ]);

      expect(samples, hasLength(2));
      expect(samples.first.ok, isFalse);
      expect(samples.first.label, 'HTTP 404');
      // The second mirror is still measured: one dead CDN says nothing about the
      // others.
      expect(samples.last.ok, isTrue);
    });

    test('a stalled mirror times out with a readable reason', () async {
      final test = SpeedTest(timeout: const Duration(milliseconds: 300));
      final sample = await test.measure(
        Mirror('slow', server.url('/slow').toString()),
      );

      expect(sample.ok, isFalse);
      expect(sample.label, contains('timed out'));
    });

    test('samples are reported as they finish, not only at the end', () async {
      final seen = <String>[];
      await SpeedTest().run([
        Mirror('a', server.url('/file').toString()),
        Mirror('b', server.url('/file').toString()),
      ], onSample: (sample) => seen.add(sample.name));

      expect(seen, ['a', 'b']);
    });
  });

  group('lan addresses', () {
    const wlan = LanInterface(name: 'wlan0', ipv4: ['192.168.1.23']);

    test('a private address from a real interface wins over a tunnel', () {
      final preferred = preferredLanAddress(const [
        LanInterface(name: 'docker0', ipv4: ['172.17.0.1']),
        wlan,
        LanInterface(name: 'tun0', ipv4: ['10.8.0.2']),
      ]);

      expect(preferred?.address, '192.168.1.23');
      expect(preferred?.interfaceName, 'wlan0');
    });

    test('a tunnel is only used when nothing else exists', () {
      final preferred = preferredLanAddress(const [
        LanInterface(name: 'tun0', ipv4: ['10.8.0.2']),
      ]);

      expect(preferred?.address, '10.8.0.2');
    });

    test('no interfaces at all is null, not an empty string', () {
      expect(preferredLanAddress(const []), isNull);
    });

    test('lanAddresses flattens one address per interface', () async {
      final all = await lanAddresses(
        read: () async => const [
          wlan,
          LanInterface(name: 'eth0', ipv4: ['10.0.0.5', '10.0.0.6']),
        ],
      );

      expect(all.map((a) => a.address), [
        '192.168.1.23',
        '10.0.0.5',
        '10.0.0.6',
      ]);
    });
  });
}
