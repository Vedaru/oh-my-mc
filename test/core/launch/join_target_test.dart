import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/launch/join_target.dart';

/// Joining a server is two launch flags, and the parse has to match what `servers.dat`
/// stores (which allows a bare address).
void main() {
  test('a bare address uses the default port', () {
    final target = JoinTarget.parse('mc.example.net');

    expect(target.host, 'mc.example.net');
    expect(target.port, 25565);
    expect(target.gameArgs, ['--server', 'mc.example.net', '--port', '25565']);
  });

  test('an explicit port is kept', () {
    final target = JoinTarget.parse('mc.example.net:25566');

    expect(target.gameArgs, ['--server', 'mc.example.net', '--port', '25566']);
  });

  test('an IPv6 literal keeps its brackets', () {
    final target = JoinTarget.parse('[::1]:25567');

    expect(target.host, '[::1]');
    expect(target.port, 25567);
  });
}
