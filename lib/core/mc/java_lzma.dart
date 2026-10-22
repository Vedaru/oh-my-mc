import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Decompresses one Mojang `.lzma` object (the "LZMA alone" stream).
///
/// Two facts about this format drive the code, both verified against real
/// catalog objects rather than assumed:
///
///  * The 13-byte header is `1 byte properties + 4 bytes dictionary size +
///    8 bytes uncompressed size`, and Mojang's objects write **`-1`** for that
///    size. `LzmaDecoder.decode` needs the length up front and returns an empty
///    buffer without it, so the length must come from the manifest's
///    `downloads.raw.size`.
///  * The properties byte encodes `lc`, `lp` and `pb` as
///    `props = (pb * 5 + lp) * 9 + lc`, and they are not always the
///    "usual" 3/0/2 — they are read, not assumed.
///
/// Runs in its own isolate: a 24 MB object is ~0.6 s of pure CPU, and doing that
/// on the UI isolate would visibly stall the window.
Future<Uint8List> decompressJavaObject({
  required Uint8List compressed,
  required int rawSize,
}) {
  // Validate before spawning: a bad object fails fast, and the guards live
  // outside the isolate so both entry points share them.
  _validate(compressed, rawSize);
  return Isolate.run(() => _decodeAlone(compressed, rawSize));
}

void _validate(Uint8List compressed, int rawSize) {
  if (compressed.length <= _headerLength) {
    throw FormatException(
      'java object is ${compressed.length}B, too short to be LZMA',
    );
  }
  if (rawSize <= 0) {
    throw FormatException('java object has no declared raw size');
  }
  final props = compressed[0];
  if (props >= 9 * 5 * 5) {
    throw FormatException('java object has invalid LZMA properties: $props');
  }
}

Uint8List _decodeAlone(Uint8List compressed, int rawSize) {
  _validate(compressed, rawSize);
  final props = compressed[0];
  final lc = props % 9;
  final rest = props ~/ 9;
  final lp = rest % 5;
  final pb = rest ~/ 5;

  final decoder = LzmaDecoder();
  decoder.reset(
    positionBits: pb,
    literalPositionBits: lp,
    literalContextBits: lc,
    resetDictionary: true,
  );

  final Uint8List out;
  try {
    out = decoder.decode(
      InputMemoryStream(Uint8List.sublistView(compressed, _headerLength)),
      rawSize,
    );
  } on RangeError catch (e) {
    // The decoder indexes its dictionary directly and reports a corrupt or
    // mis-sized stream as a RangeError. Callers switch on FormatException to
    // mean "this object is unusable", so a raw RangeError must not escape.
    throw FormatException('java object is corrupt: ${e.message}');
  }
  if (out.length != rawSize) {
    throw FormatException(
      'LZMA object decoded to ${out.length}B, expected ${rawSize}B',
    );
  }
  return out;
}

const _headerLength = 13;

/// Blocks the calling isolate; for tests that want the decode inline.
Uint8List decodeJavaObjectSync({
  required Uint8List compressed,
  required int rawSize,
}) => _decodeAlone(compressed, rawSize);
