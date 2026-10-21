// Verifies that a built launcher binary really has the architecture we think it
// does. CI runs this after every build so a mis-targeted (or silently x64)
// artifact can never be published under an arch-specific name.
//
//   dart run tool/verify_binary_arch.dart --file=<path> --expect=<target>
//   targets: linux-x64, windows-x64
//
// Exits 0 on match, 1 on mismatch/unreadable, 64 on bad usage.
library;

import 'dart:io';
import 'dart:typed_data';

enum BinaryFormat { elf, pe, machO, machOFat, unknown }

const _elfMachineX64 = 0x3e;
const _elfMachineAarch64 = 0xb7;
const _peMachineAmd64 = 0x8664;
const _peMachineArm64 = 0xaa64;
const _machCpuX64 = 0x01000007;
const _machCpuArm64 = 0x0100000c;

void main(List<String> argv) {
  final args = _parseArgs(argv);
  final path = args['file'];
  final expect = args['expect'];
  if (path == null || expect == null) {
    stderr.writeln(
      'usage: verify_binary_arch.dart --file=<path> --expect=<${_knownTargets.join('|')}>',
    );
    exit(64);
  }

  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('FAIL  $path does not exist');
    exit(1);
  }

  final found = describeBinary(file.readAsBytesSync());
  final ok = matchesTarget(found, expect);

  stdout.writeln('${ok ? 'OK  ' : 'FAIL'}  $path');
  stdout.writeln(
    '      format=${found.format.name} arch=${found.arch ?? '?'} '
    '${found.detail.isEmpty ? '' : '(${found.detail})'}  expected=$expect',
  );
  exit(ok ? 0 : 1);
}

const _knownTargets = ['linux-x64', 'windows-x64'];

Map<String, String> _parseArgs(List<String> argv) {
  final out = <String, String>{};
  for (final a in argv) {
    if (!a.startsWith('--')) continue;
    final eq = a.indexOf('=');
    if (eq != -1) {
      out[a.substring(2, eq)] = a.substring(eq + 1);
    }
  }
  return out;
}

class BinaryInfo {
  BinaryInfo(
    this.format,
    this.arch, [
    this.detail = '',
    this.arches = const [],
  ]);
  final BinaryFormat format;
  final String? arch;
  final String detail;
  final List<String> arches;
}

BinaryInfo describeBinary(Uint8List b) {
  if (b.length < 8) {
    return BinaryInfo(BinaryFormat.unknown, null, 'file too short');
  }

  // ELF: 0x7f 'E' 'L' 'F'
  if (b[0] == 0x7f && b[1] == 0x45 && b[2] == 0x4c && b[3] == 0x46) {
    final is64 = b[4] == 2;
    final le = b[5] == 1;
    final machine = le ? b[18] | (b[19] << 8) : (b[18] << 8) | b[19];
    return BinaryInfo(
      BinaryFormat.elf,
      _elfArch(machine),
      is64 ? 'ELF64' : 'ELF32',
    );
  }

  // Mach-O thin (64-bit LE) or fat (big-endian) — handy when the macOS build
  // is verified on a developer machine rather than in CI.
  // File bytes are CF FA ED FE for a 64-bit LE Mach-O; read as a LE u32 that
  // is 0xFEEDFACF, not the 0xCFFAEDFE you get by reading the bytes big-endian.
  final magicLE = b[0] | (b[1] << 8) | (b[2] << 16) | (b[3] << 24);
  if (magicLE == 0xfeedfacf || magicLE == 0xfeedface) {
    return BinaryInfo(BinaryFormat.machO, _machCpu(_u32le(b, 4)), 'thin');
  }
  final magicBE = (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
  if (magicBE == 0xcafebabe || magicBE == 0xcafebabf) {
    final count = _u32be(b, 4);
    final arches = <String>[];
    var off = 8;
    for (var i = 0; i < count && off + 4 <= b.length; i++) {
      arches.add(_machCpu(_u32be(b, off)));
      off += magicBE == 0xcafebabf ? 32 : 20;
    }
    return BinaryInfo(
      BinaryFormat.machOFat,
      arches.join('+'),
      'universal x$count',
      arches,
    );
  }

  // PE: 'MZ' at 0, e_lfanew at 0x3c, then 'PE\0\0'.
  if (b[0] == 0x4d && b[1] == 0x5a) {
    if (b.length < 0x40) {
      return BinaryInfo(BinaryFormat.pe, null, 'truncated MZ header');
    }
    final peOff = _u32le(b, 0x3c);
    if (peOff + 6 > b.length) {
      return BinaryInfo(BinaryFormat.pe, null, 'bad e_lfanew');
    }
    if (b[peOff] != 0x50 || b[peOff + 1] != 0x45) {
      return BinaryInfo(BinaryFormat.pe, null, 'missing PE signature');
    }
    final machine = b[peOff + 4] | (b[peOff + 5] << 8);
    return BinaryInfo(BinaryFormat.pe, _peArch(machine), 'PE');
  }

  return BinaryInfo(
    BinaryFormat.unknown,
    null,
    'magic ${b.sublist(0, 4).map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}',
  );
}

String _elfArch(int machine) => switch (machine) {
  _elfMachineX64 => 'x64',
  _elfMachineAarch64 => 'arm64',
  _ => 'machine-0x${machine.toRadixString(16)}',
};

String _peArch(int machine) => switch (machine) {
  _peMachineAmd64 => 'x64',
  _peMachineArm64 => 'arm64',
  _ => 'machine-0x${machine.toRadixString(16)}',
};

String _machCpu(int cpu) => switch (cpu) {
  _machCpuX64 => 'x64',
  _machCpuArm64 => 'arm64',
  _ => 'cpu-0x${cpu.toRadixString(16)}',
};

int _u32le(Uint8List b, int o) =>
    b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

int _u32be(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

bool matchesTarget(BinaryInfo f, String expect) => switch (expect) {
  'linux-x64' => f.format == BinaryFormat.elf && f.arch == 'x64',
  'windows-x64' => f.format == BinaryFormat.pe && f.arch == 'x64',
  _ => false,
};
