import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/app/version.dart';

void main() {
  test('the version constant matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*([0-9.]+)',
      multiLine: true,
    ).firstMatch(pubspec);

    // The updater compares this string with release tags: a stale constant means the
    // launcher either misses every update or offers an old one forever.
    expect(match?.group(1), appVersion);
  });
}
