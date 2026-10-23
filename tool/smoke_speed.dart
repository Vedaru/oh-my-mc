// Real-network check for the two download sources the launcher can switch between.
//
// The first version of this list pointed at URLs nobody had opened - a fabricated
// `piston-data` object and a guessed Modrinth CDN path - which answered 404 and 400
// and made the speed test look broken. Run this after touching `Mirror.defaults`:
//
//   dart run tool/smoke_speed.dart
import 'dart:io';

import 'package:oh_my_mc/core/diagnostics/speed_test.dart';

Future<void> main() async {
  final test = SpeedTest(maxBytes: 512 * 1024);
  try {
    for (final mirror in Mirror.defaults) {
      final sample = await test.measure(mirror);
      stdout.writeln(
        '${mirror.name.padRight(10)} ${sample.label.padRight(12)} '
        'bytes=${sample.bytes} in ${sample.elapsed.inMilliseconds} ms',
      );
      if (!sample.ok) stdout.writeln('  url: ${mirror.url}');
    }
  } finally {
    test.close();
  }
}
