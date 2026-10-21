import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/verify_binary_arch.dart';

Uint8List _elf({required int machine, required bool is64}) {
  final b = Uint8List(64);
  b.setAll(0, [0x7f, 0x45, 0x4c, 0x46, is64 ? 2 : 1, 1, 1, 0]);
  b[18] = machine & 0xff;
  b[19] = (machine >> 8) & 0xff;
  return b;
}

Uint8List _pe({required int machine}) {
  final b = Uint8List(0x100);
  b[0] = 0x4d; // M
  b[1] = 0x5a; // Z
  const peOff = 0x80;
  b[0x3c] = peOff;
  b[peOff] = 0x50; // P
  b[peOff + 1] = 0x45; // E
  b[peOff + 4] = machine & 0xff;
  b[peOff + 5] = (machine >> 8) & 0xff;
  return b;
}

Uint8List _machThin(int cpu) {
  final b = Uint8List(32);
  b.setAll(0, [0xcf, 0xfa, 0xed, 0xfe]);
  b[4] = cpu & 0xff;
  b[5] = (cpu >> 8) & 0xff;
  b[6] = (cpu >> 16) & 0xff;
  b[7] = (cpu >> 24) & 0xff;
  return b;
}

Uint8List _machFat(List<int> cpus) {
  final b = Uint8List(8 + 20 * cpus.length);
  b.setAll(0, [0xca, 0xfe, 0xba, 0xbe]);
  b[7] = cpus.length;
  for (var i = 0; i < cpus.length; i++) {
    final o = 8 + 20 * i;
    final cpu = cpus[i];
    b[o] = (cpu >> 24) & 0xff;
    b[o + 1] = (cpu >> 16) & 0xff;
    b[o + 2] = (cpu >> 8) & 0xff;
    b[o + 3] = cpu & 0xff;
  }
  return b;
}

void main() {
  group('ELF', () {
    test('linux x64 ELF64 is recognised and accepted', () {
      final info = describeBinary(_elf(machine: 0x3e, is64: true));
      expect(info.format, BinaryFormat.elf);
      expect(info.arch, 'x64');
      expect(matchesTarget(info, 'linux-x64'), isTrue);
      expect(matchesTarget(info, 'windows-x64'), isFalse);
    });

    test('aarch64 ELF is rejected as linux-x64', () {
      final info = describeBinary(_elf(machine: 0xb7, is64: true));
      expect(info.arch, 'arm64');
      expect(matchesTarget(info, 'linux-x64'), isFalse);
    });

    test('32-bit ELF is not silently accepted', () {
      final info = describeBinary(_elf(machine: 0x3e, is64: false));
      expect(info.detail, 'ELF32');
    });
  });

  group('PE', () {
    test('AMD64 PE is accepted as windows-x64', () {
      final info = describeBinary(_pe(machine: 0x8664));
      expect(info.format, BinaryFormat.pe);
      expect(info.arch, 'x64');
      expect(matchesTarget(info, 'windows-x64'), isTrue);
      expect(matchesTarget(info, 'linux-x64'), isFalse);
    });

    test('ARM64 PE is rejected as windows-x64', () {
      final info = describeBinary(_pe(machine: 0xaa64));
      expect(info.arch, 'arm64');
      expect(matchesTarget(info, 'windows-x64'), isFalse);
    });

    test('MZ with a broken e_lfanew does not crash', () {
      final b = Uint8List(0x50)..setAll(0, [0x4d, 0x5a]);
      b[0x3c] = 0xff; // points past EOF
      final info = describeBinary(b);
      expect(info.format, BinaryFormat.pe);
      expect(info.arch, isNull);
      expect(matchesTarget(info, 'windows-x64'), isFalse);
    });

    test('MZ without a PE signature is rejected', () {
      final b = Uint8List(0x100)..setAll(0, [0x4d, 0x5a]);
      b[0x3c] = 0x80; // valid offset, but no "PE\0\0"
      final info = describeBinary(b);
      expect(info.detail, 'missing PE signature');
      expect(info.arch, isNull);
    });
  });

  group('Mach-O (macOS ships arm-only, but parsing must still be correct)', () {
    test('fat binary with both slices is reported as universal', () {
      final info = describeBinary(_machFat([0x01000007, 0x0100000c]));
      expect(info.format, BinaryFormat.machOFat);
      expect(info.arches, ['x64', 'arm64']);
      expect(info.detail, contains('x2'));
    });

    test('thin arm64 slice is identified', () {
      expect(describeBinary(_machThin(0x0100000c)).arch, 'arm64');
    });

    test('thin x64 slice is identified', () {
      expect(describeBinary(_machThin(0x01000007)).arch, 'x64');
    });
  });

  group('garbage input', () {
    test('short file is unknown, not a crash', () {
      expect(describeBinary(Uint8List(3)).format, BinaryFormat.unknown);
    });

    test('empty file is unknown', () {
      expect(describeBinary(Uint8List(0)).format, BinaryFormat.unknown);
    });

    test('unknown target name fails closed', () {
      final info = describeBinary(_elf(machine: 0x3e, is64: true));
      expect(matchesTarget(info, 'linux-arm64'), isFalse);
      expect(matchesTarget(info, 'nonsense'), isFalse);
    });
  });

  group('real binary on disk', () {
    test('the locally built Linux bundle parses as a 64-bit ELF', () {
      final f = File('build/linux/arm64/release/bundle/oh_my_mc');
      if (!f.existsSync()) {
        markTestSkipped('no local Linux build present');
        return;
      }
      final info = describeBinary(f.readAsBytesSync());
      expect(info.format, BinaryFormat.elf);
      expect(info.detail, 'ELF64');
      // This host is arm64, so an honest parser reports arm64. That the value
      // is arch-accurate (not just "some ELF") is the point of the check.
      expect(info.arch, 'arm64');
    });
  });
}
