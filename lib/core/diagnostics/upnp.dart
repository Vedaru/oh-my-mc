import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A UPnP gateway (an IGD, usually the router) that can open a port.
class UpnpGateway {
  const UpnpGateway({
    required this.friendlyName,
    required this.controlUrl,
    required this.serviceType,
    required this.localAddress,
  });

  final String friendlyName;
  final Uri controlUrl;
  final String serviceType;

  /// The address the router sees this machine at, which is also the address the SOAP
  /// calls must name as the internal client.
  final String localAddress;
}

/// A port mapping the gateway accepted.
class PortMapping {
  const PortMapping({
    required this.externalPort,
    required this.internalPort,
    required this.externalAddress,
  });

  final int externalPort;
  final int internalPort;

  /// The address a friend outside the LAN types, or null when the gateway refuses to
  /// report one (many ISPs put the router behind another NAT).
  final String? externalAddress;

  String? get shareAddress =>
      externalAddress == null ? null : '$externalAddress:$externalPort';
}

/// UPnP IGD port mapping: SSDP discovery, then two SOAP calls.
///
/// The point is narrow: a world opened to LAN is reachable only inside the house, and
/// the game's port is random per session. With the port from the LAN announcement,
/// this makes the world reachable from outside by opening exactly that port and
/// nothing else.
///
/// [discoverControlUrl] is injectable because SSDP is multicast UDP - a test cannot
/// reliably fake it in-process, and everything after discovery (the XML, the SOAP
/// bodies) is where the bugs live.
class UpnpClient {
  UpnpClient({
    HttpClient? client,
    Future<Uri?> Function()? discoverControlUrl,
    this.timeout = const Duration(seconds: 4),
  }) : _client = client ?? HttpClient(),
       _discover = discoverControlUrl;

  final HttpClient _client;
  final Future<Uri?> Function()? _discover;
  final Duration timeout;

  /// Finds the router's IGD service.
  Future<UpnpGateway?> discover({String? localAddress}) async {
    final location = await (_discover?.call() ?? _ssdpLocation());
    if (location == null) return null;

    final description = await _get(location);
    if (description == null) return null;

    // The description is XML with namespaces and a device tree; a real parser for it
    // would be a dependency for three fields, and the two values needed are unique
    // strings in the document.
    final igd = RegExp(
      // The service type names the *service*, not the device: a real IGD says
      // `urn:schemas-upnp-org:service:WANIPConnection:1` while sitting inside an
      // `InternetGatewayDevice` device.
      r'<serviceType>([^<]*(?:WANIPConnection|WANPPPConnection)[^<]*)</serviceType>'
      r'\s*<serviceId>[^<]*</serviceId>\s*<controlURL>([^<]+)</controlURL>',
      caseSensitive: false,
    ).firstMatch(description);
    if (igd == null) return null;

    final friendly = RegExp(
      r'<friendlyName>([^<]*)</friendlyName>',
      caseSensitive: false,
    ).firstMatch(description);

    return UpnpGateway(
      friendlyName: friendly?.group(1) ?? 'router',
      // A relative control URL is relative to the description's location, which is
      // the usual case and the reason this is resolved rather than parsed.
      controlUrl: location.resolve(igd.group(2)!.trim()),
      serviceType: igd.group(1)!.trim(),
      localAddress: localAddress ?? await localIpv4(),
    );
  }

  /// Opens [externalPort] → [internalPort] for [lease].
  Future<PortMapping?> mapPort({
    required UpnpGateway gateway,
    required int internalPort,
    int? externalPort,
    String description = 'oh-my-mc',
    Duration lease = const Duration(hours: 2),
  }) async {
    final port = externalPort ?? internalPort;
    final body = _soap(gateway.serviceType, 'AddPortMapping', '''
<NewRemoteHost></NewRemoteHost>
<NewExternalPort>$port</NewExternalPort>
<NewProtocol>TCP</NewProtocol>
<NewInternalPort>$internalPort</NewInternalPort>
<NewInternalClient>${gateway.localAddress}</NewInternalClient>
<NewEnabled>1</NewEnabled>
<NewPortMappingDescription>$description</NewPortMappingDescription>
<NewLeaseDuration>${lease.inSeconds}</NewLeaseDuration>''');
    final response = await _post(gateway.controlUrl, body);
    if (response == null) return null;
    // A refusal is an HTTP 500 with a UPnP error code in the body; `_post` reports
    // that as null, so anything here is an accepted mapping.
    return PortMapping(
      externalPort: port,
      internalPort: internalPort,
      externalAddress: await externalAddress(gateway),
    );
  }

  /// Closes a mapping this launcher created.
  Future<bool> unmapPort({
    required UpnpGateway gateway,
    required int externalPort,
  }) async {
    final response = await _post(
      gateway.controlUrl,
      _soap(gateway.serviceType, 'DeletePortMapping', '''
<NewRemoteHost></NewRemoteHost>
<NewExternalPort>$externalPort</NewExternalPort>
<NewProtocol>TCP</NewProtocol>'''),
    );
    return response != null;
  }

  /// The address the router believes it has from the ISP.
  Future<String?> externalAddress(UpnpGateway gateway) async {
    final response = await _post(
      gateway.controlUrl,
      _soap(gateway.serviceType, 'GetExternalIPAddress', ''),
    );
    if (response == null) return null;
    final match = RegExp(
      r'<NewExternalIPAddress>([^<]*)</NewExternalIPAddress>',
      caseSensitive: false,
    ).firstMatch(response);
    final value = match?.group(1);
    if (value == null || value.isEmpty || value == '0.0.0.0') return null;
    return value;
  }

  /// SSDP: multicast an M-SEARCH and take the first reply that names an IGD.
  Future<Uri?> _ssdpLocation() async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      const search =
          'M-SEARCH * HTTP/1.1\r\n'
          'HOST: 239.255.255.250:1900\r\n'
          'MAN: "ssdp:discover"\r\n'
          'MX: 2\r\n'
          'ST: urn:schemas-upnp-org:device:InternetGatewayDevice:1\r\n\r\n';
      socket.send(
        utf8.encode(search),
        InternetAddress('239.255.255.250'),
        1900,
      );

      final completer = Completer<Uri?>();
      final subscription = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        final text = utf8.decode(datagram.data, allowMalformed: true);
        final location = RegExp(
          r'^location:\s*(\S+)',
          caseSensitive: false,
          multiLine: true,
        ).firstMatch(text);
        if (location != null && !completer.isCompleted) {
          completer.complete(Uri.tryParse(location.group(1)!.trim()));
        }
      });
      final timer = Timer(timeout, () {
        if (!completer.isCompleted) completer.complete(null);
      });
      final result = await completer.future;
      timer.cancel();
      await subscription.cancel();
      return result;
    } on SocketException {
      return null;
    } finally {
      socket.close();
    }
  }

  String _soap(String serviceType, String action, String arguments) =>
      '<?xml version="1.0"?>'
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
      's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
      '<s:Body><u:$action xmlns:u="$serviceType">$arguments</u:$action></s:Body>'
      '</s:Envelope>';

  Future<String?> _get(Uri url) async {
    try {
      final request = await _client.getUrl(url).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }
      return await response.transform(utf8.decoder).join();
    } on Object {
      return null;
    }
  }

  Future<String?> _post(Uri url, String body) async {
    try {
      final request = await _client.postUrl(url).timeout(timeout);
      request.headers.contentType = ContentType(
        'text',
        'xml',
        charset: 'utf-8',
      );
      request.headers.set(
        'SOAPAction',
        '"${_serviceOf(body)}#${_actionOf(body)}"',
      );
      request.write(body);
      final response = await request.close().timeout(timeout);
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) return null;
      return text;
    } on Object {
      return null;
    }
  }

  static String _serviceOf(String body) =>
      RegExp(r'xmlns:u="([^"]+)"').firstMatch(body)?.group(1) ?? '';

  static String _actionOf(String body) =>
      RegExp(r'<u:(\w+)').firstMatch(body)?.group(1) ?? '';

  void close() => _client.close(force: true);
}

/// This machine's LAN address, for the SOAP internal-client field.
Future<String> localIpv4() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
    includeLinkLocal: false,
  );
  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      if (address.isLoopback || address.isLinkLocal) continue;
      return address.address;
    }
  }
  return '127.0.0.1';
}
