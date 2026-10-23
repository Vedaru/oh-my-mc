import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/diagnostics/lan_discovery.dart';
import 'package:oh_my_mc/core/diagnostics/upnp.dart';

/// A router stand-in: serves the device description and accepts SOAP calls,
/// recording what it was asked to do.
class _FakeGateway {
  _FakeGateway._(this._server);

  final HttpServer _server;
  final calls = <String>[];

  static Future<_FakeGateway> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeGateway._(server);
    server.listen((request) async {
      final body = request.method == 'POST'
          ? await utf8.decoder.bind(request).join()
          : '';
      fake.calls.add('${request.method} ${request.uri.path} $body');
      request.response.headers.contentType = ContentType('text', 'xml');

      if (request.uri.path == '/description.xml') {
        request.response.write('''
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <device>
    <friendlyName>Test Router</friendlyName>
    <deviceList><device><deviceList><device>
      <serviceList><service>
        <serviceType>urn:schemas-upnp-org:service:WANIPConnection:1</serviceType>
        <serviceId>urn:upnp-org:serviceId:WANIPConn1</serviceId>
        <controlURL>/control</controlURL>
      </service></serviceList>
    </device></deviceList></device></deviceList>
  </device>
</root>''');
      } else if (request.uri.path == '/control') {
        if (body.contains('GetExternalIPAddress')) {
          request.response.write(
            '<NewExternalIPAddress>203.0.113.7</NewExternalIPAddress>',
          );
        } else {
          request.response.write('<ok/>');
        }
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    return fake;
  }

  Uri get location =>
      Uri.parse('http://127.0.0.1:${_server.port}/description.xml');
  Future<void> close() => _server.close(force: true);

  String get lastCall => calls.last;
}

void main() {
  group('lan announcements', () {
    test('reads the motd and the port the game opened', () {
      final announcement = LanAnnouncement.parse(
        '[MOTD]Vedaru\'s World[/MOTD][AD]54321[/AD]',
      );

      expect(announcement?.motd, "Vedaru's World");
      expect(announcement?.port, 54321);
    });

    test('ignores keys mods append after the two it needs', () {
      final announcement = LanAnnouncement.parse(
        '[MOTD]Vanilla[/MOTD][AD]25565[/AD][SOMEMOD]whatever[/SOMEMOD]',
      );

      expect(announcement?.port, 25565);
    });

    test('anything that is not an announcement is null', () {
      expect(LanAnnouncement.parse('hello'), isNull);
      expect(LanAnnouncement.parse('[MOTD]x[/MOTD]'), isNull);
      expect(LanAnnouncement.parse('[AD]notaport[/AD][MOTD]x[/MOTD]'), isNull);
      // Out of range: a port the socket could not have opened.
      expect(LanAnnouncement.parse('[MOTD]x[/MOTD][AD]70000[/AD]'), isNull);
    });

    test(
      'discover returns what the listener found, deduplicated by address',
      () async {
        final worlds = await const LanDiscovery().discover(
          listener: (window) async => const [
            LanWorld(motd: 'A', port: 25565, address: '192.168.1.9'),
          ],
        );

        expect(worlds.single.shareAddress, '192.168.1.9:25565');
      },
    );
  });

  group('upnp', () {
    late _FakeGateway gateway;
    late UpnpClient client;

    setUp(() async {
      gateway = await _FakeGateway.start();
      client = UpnpClient(discoverControlUrl: () async => gateway.location);
    });

    tearDown(() async {
      client.close();
      await gateway.close();
    });

    test('discovers the IGD service and its control URL', () async {
      final found = await client.discover(localAddress: '192.168.1.23');

      expect(found, isNotNull);
      expect(found!.friendlyName, 'Test Router');
      expect(found.serviceType, contains('WANIPConnection'));
      // The control URL in the document is relative; it has to resolve against the
      // description's location.
      expect(found.controlUrl.toString(), endsWith('/control'));
      expect(found.localAddress, '192.168.1.23');
    });

    test('maps the port the game announced, and reports the external address', () async {
      final found = await client.discover(localAddress: '192.168.1.23');

      final mapping = await client.mapPort(
        gateway: found!,
        internalPort: 54321,
      );

      expect(mapping?.externalPort, 54321);
      expect(mapping?.shareAddress, '203.0.113.7:54321');
      // The SOAP body must carry the port, the protocol and this machine as the
      // internal client - the three things a router needs and the launcher gets wrong
      // when it guesses.
      final soap = gateway.calls.firstWhere(
        (call) => call.contains('AddPortMapping'),
      );
      expect(soap, contains('<NewInternalPort>54321</NewInternalPort>'));
      expect(soap, contains('<NewProtocol>TCP</NewProtocol>'));
      expect(
        soap,
        contains('<NewInternalClient>192.168.1.23</NewInternalClient>'),
      );
    });

    test('a mapping can be removed again', () async {
      final found = await client.discover(localAddress: '192.168.1.23');

      final removed = await client.unmapPort(
        gateway: found!,
        externalPort: 54321,
      );

      expect(removed, isTrue);
      expect(
        gateway.calls.any((call) => call.contains('DeletePortMapping')),
        isTrue,
      );
    });

    test('no gateway means no mapping, not an exception', () async {
      final offline = UpnpClient(discoverControlUrl: () async => null);

      expect(await offline.discover(), isNull);
      offline.close();
    });

    test('a gateway without an IGD service is not usable', () async {
      // A description that parses but has no WANIPConnection: a plain switch or an
      // access point.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.write('<root><device><serviceList/></device></root>');
        await request.response.close();
      });
      final bare = UpnpClient(
        discoverControlUrl: () async =>
            Uri.parse('http://127.0.0.1:${server.port}/description.xml'),
      );

      expect(await bare.discover(localAddress: '192.168.1.2'), isNull);

      bare.close();
      await server.close(force: true);
    });
  });
}
