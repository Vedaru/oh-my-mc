import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Reads one entry out of a zip without loading the archive.
///
/// The mod scanner needs three short JSON/TOML documents from each jar, and the
/// previous implementation decoded the whole file to get them: a 120 MB modpack
/// jar cost 120 MB of memory and a full inflate per mod, on the UI thread, for a
/// 400-byte descriptor. This walks the central directory (a few kilobytes at the
/// end of the file) and inflates exactly one entry.
///
/// Only what a metadata read needs is supported: stored and deflated entries, no
/// encryption, no zip64. Those cover every jar a mod loader produces, and anything
/// else reports "unreadable" instead of guessing.
class ZipEntryReader {
  ZipEntryReader._(this._file, this._length);

  final RandomAccessFile _file;
  final int _length;

  static const _eocdSignature = 0x06054b50;
  static const _centralSignature = 0x02014b50;
  static const _localSignature = 0x04034b50;
  static const _eocdSearchWindow = 66 * 1024;

  /// The central directory, parsed once so [read] can be called for several names.
  late final Map<String, _Entry> _entries = _readCentralDirectory();

  static Future<ZipEntryReader> open(File file) async {
    final handle = await file.open();
    final length = await handle.length();
    return ZipEntryReader._(handle, length);
  }

  Future<void> close() => _file.close();

  /// The first of [names] that exists, decoded as UTF-8, or `null`.
  Future<String?> readFirst(List<String> names) async {
    for (final name in names) {
      final bytes = await read(name);
      if (bytes != null) return utf8.decode(bytes, allowMalformed: true);
    }
    return null;
  }

  Future<Uint8List?> read(String name) async {
    final entry = _entries[name];
    if (entry == null) return null;

    await _file.setPosition(entry.localHeaderOffset);
    final header = await _file.read(30);
    if (header.lengthInBytes < 30) return null;
    final headerData = ByteData.sublistView(header);
    if (headerData.getUint32(0, Endian.little) != _localSignature) return null;

    final method = headerData.getUint16(8, Endian.little);
    final compressedSize = headerData.getUint32(18, Endian.little);
    final nameLength = headerData.getUint16(26, Endian.little);
    final extraLength = headerData.getUint16(28, Endian.little);
    if (compressedSize == 0 || compressedSize > _length) return null;

    await _file.setPosition(
      entry.localHeaderOffset + 30 + nameLength + extraLength,
    );
    final raw = await _file.read(compressedSize);
    if (raw.lengthInBytes != compressedSize) return null;

    return switch (method) {
      // 0 = stored, 8 = deflate. Anything else (bzip2, lzma) is not a jar.
      0 => Uint8List.fromList(raw),
      8 => Uint8List.fromList(
        // `raw: true`: zip stores a raw deflate stream, without the zlib header
        // that the default decoder expects.
        ZLibDecoder(raw: true).convert(raw),
      ),
      _ => null,
    };
  }

  Map<String, _Entry> _readCentralDirectory() {
    // The end-of-central-directory record is in the last 64 KB (its comment field
    // is at most 65535 bytes), so only that window is read.
    final window = _length < _eocdSearchWindow ? _length : _eocdSearchWindow;
    _file.setPositionSync(_length - window);
    final tail = _file.readSync(window);
    final data = ByteData.sublistView(tail);

    var eocd = -1;
    for (var i = tail.lengthInBytes - 22; i >= 0; i--) {
      if (data.getUint32(i, Endian.little) == _eocdSignature) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) return const {};

    final count = data.getUint16(eocd + 10, Endian.little);
    final centralOffset = data.getUint32(eocd + 16, Endian.little);
    final centralSize = data.getUint32(eocd + 12, Endian.little);
    if (centralOffset <= 0 || centralOffset + centralSize > _length) {
      return const {};
    }

    _file.setPositionSync(centralOffset);
    final central = _file.readSync(centralSize);
    final centralData = ByteData.sublistView(central);

    final entries = <String, _Entry>{};
    var offset = 0;
    for (var i = 0; i < count; i++) {
      if (offset + 46 > central.lengthInBytes) break;
      if (centralData.getUint32(offset, Endian.little) != _centralSignature) {
        break;
      }
      final nameLength = centralData.getUint16(offset + 28, Endian.little);
      final extraLength = centralData.getUint16(offset + 30, Endian.little);
      final commentLength = centralData.getUint16(offset + 32, Endian.little);
      final localOffset = centralData.getUint32(offset + 42, Endian.little);
      final nameBytes = central.sublist(offset + 46, offset + 46 + nameLength);
      entries[utf8.decode(nameBytes, allowMalformed: true)] = _Entry(
        localOffset,
      );
      offset += 46 + nameLength + extraLength + commentLength;
    }
    return entries;
  }
}

class _Entry {
  const _Entry(this.localHeaderOffset);

  final int localHeaderOffset;
}
