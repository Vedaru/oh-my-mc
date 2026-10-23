import 'dart:io';

/// One network interface and its IPv4 addresses, as plain data.
///
/// Not `NetworkInterface` from `dart:io`: that class is abstract and cannot be
/// constructed in a test, which would leave the ranking below untestable.
class LanInterface {
  const LanInterface({required this.name, required this.ipv4});

  final String name;
  final List<String> ipv4;
}

/// A local address another machine on the same network can reach.
class LanAddress {
  const LanAddress({required this.address, required this.interfaceName});

  final String address;
  final String interfaceName;

  String get display => address;
}

/// The machine's LAN interfaces.
///
/// Loopback and link-local are filtered at the source: they cannot be reached from
/// another machine, and offering `127.0.0.1` in a dialog about LAN play is actively
/// misleading. IPv6 is not read for the same reason it is not typed by hand.
Future<List<LanInterface>> lanInterfaces({
  Future<List<LanInterface>> Function()? read,
}) async {
  if (read != null) return read();
  final list = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
    includeLinkLocal: false,
  );
  return [
    for (final interface in list)
      LanInterface(
        name: interface.name,
        ipv4: [
          for (final address in interface.addresses)
            if (!address.isLoopback && !address.isLinkLocal) address.address,
        ],
      ),
  ].where((interface) => interface.ipv4.isNotEmpty).toList();
}

/// Every address worth sharing.
Future<List<LanAddress>> lanAddresses({
  Future<List<LanInterface>> Function()? read,
}) async => [
  for (final interface in await lanInterfaces(read: read))
    for (final ip in interface.ipv4)
      LanAddress(address: ip, interfaceName: interface.name),
];

/// The single address most likely to be the one to share, or `null`.
///
/// Ranks a private range (RFC1918) above anything else and a real interface above a
/// tunnel: a VPN or a Docker bridge is not where the game listens, and picking one
/// gives the friend an address that silently does not work.
LanAddress? preferredLanAddress(List<LanInterface> interfaces) {
  final all = [
    for (final interface in interfaces)
      for (final ip in interface.ipv4)
        LanAddress(address: ip, interfaceName: interface.name),
  ];
  if (all.isEmpty) return null;

  bool isPrivate(String ip) =>
      ip.startsWith('192.168.') ||
      ip.startsWith('10.') ||
      RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip);
  bool isTunnel(String name) => RegExp(
    r'^(tun|tap|docker|br-|virbr|veth|zt)',
    caseSensitive: false,
  ).hasMatch(name);

  int score(LanAddress address) =>
      (isPrivate(address.address) ? 2 : 0) +
      (isTunnel(address.interfaceName) ? 0 : 1);

  final ranked = [...all]..sort((a, b) => score(b).compareTo(score(a)));
  return ranked.first;
}
