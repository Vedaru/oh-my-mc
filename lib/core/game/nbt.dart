/// The smallest NBT reader/writer that covers `servers.dat`.
///
/// `servers.dat` is an uncompressed NBT compound holding a list of server
/// compounds (name, ip, icon, acceptTextures). Minecraft's full format has eleven
/// tags and nested arrays; this implements the seven that a server list actually
/// uses, and refuses everything else loudly instead of writing a file the game will
/// reject.
library;

import 'dart:convert';
import 'dart:typed_data';

/// A tag value. Numbers are stored as their widened form; the tag type is what the
/// writer needs, so it is kept alongside.
sealed class NbtTag {
  const NbtTag();
}

class NbtString extends NbtTag {
  const NbtString(this.value);
  final String value;
}

class NbtByte extends NbtTag {
  const NbtByte(this.value);
  final int value;
}

class NbtShort extends NbtTag {
  const NbtShort(this.value);
  final int value;
}

class NbtInt extends NbtTag {
  const NbtInt(this.value);
  final int value;
}

class NbtLong extends NbtTag {
  const NbtLong(this.value);
  final int value;
}

class NbtCompound extends NbtTag {
  NbtCompound([Map<String, NbtTag>? values]) : values = values ?? {};

  final Map<String, NbtTag> values;

  String? string(String key) {
    final value = values[key];
    return value is NbtString ? value.value : null;
  }
}

class NbtList extends NbtTag {
  NbtList(this.elementType, [List<NbtTag>? items]) : items = items ?? [];

  /// NBT tag id of the elements; every element of a list shares one type.
  final int elementType;
  final List<NbtTag> items;
}

/// Tag ids, as the file format numbers them.
abstract final class NbtTagId {
  static const byte = 1;
  static const short = 2;
  static const int32 = 3;
  static const long = 4;
  static const string = 8;
  static const list = 9;
  static const compound = 10;
}

class NbtException implements Exception {
  const NbtException(this.message);
  final String message;

  @override
  String toString() => 'NbtException: $message';
}

/// Reads one root compound from [bytes].
NbtCompound readNbt(Uint8List bytes) => _Reader(bytes).readRoot();

class _Reader {
  _Reader(this.bytes) : _view = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData _view;
  var _offset = 0;

  NbtCompound readRoot() {
    final type = _readByte();
    if (type != NbtTagId.compound) {
      throw NbtException('root tag is $type, expected a compound');
    }
    _readString(); // root name, always empty in practice
    return _readPayload(NbtTagId.compound) as NbtCompound;
  }

  NbtTag _readPayload(int type) => switch (type) {
    NbtTagId.byte => NbtByte(_readByte()),
    NbtTagId.short => NbtShort(_readShort()),
    NbtTagId.int32 => NbtInt(_readInt()),
    NbtTagId.long => NbtLong(_readLong()),
    NbtTagId.string => NbtString(_readString()),
    NbtTagId.list => _readList(),
    NbtTagId.compound => _readCompound(),
    _ => throw NbtException('unsupported tag type $type'),
  };

  NbtCompound _readCompound() {
    final out = NbtCompound();
    while (true) {
      final type = _readByte();
      if (type == 0) return out;
      final name = _readString();
      out.values[name] = _readPayload(type);
    }
  }

  NbtList _readList() {
    final elementType = _readByte();
    final length = _readInt();
    if (length < 0) throw const NbtException('negative list length');
    return NbtList(elementType, [
      for (var i = 0; i < length; i++) _readPayload(elementType),
    ]);
  }

  int _readByte() {
    _need(1);
    final value = _view.getInt8(_offset);
    _offset += 1;
    return value;
  }

  int _readShort() {
    _need(2);
    final value = _view.getInt16(_offset);
    _offset += 2;
    return value;
  }

  int _readInt() {
    _need(4);
    final value = _view.getInt32(_offset);
    _offset += 4;
    return value;
  }

  int _readLong() {
    _need(8);
    final value = _view.getInt64(_offset);
    _offset += 8;
    return value;
  }

  String _readString() {
    _need(2);
    final length = _view.getUint16(_offset);
    _offset += 2;
    _need(length);
    final value = utf8.decode(
      bytes.sublist(_offset, _offset + length),
      allowMalformed: true,
    );
    _offset += length;
    return value;
  }

  void _need(int count) {
    if (_offset + count > bytes.length) {
      throw const NbtException('truncated NBT data');
    }
  }
}

/// Writes a root compound.
Uint8List writeNbt(NbtCompound root) {
  final builder = BytesBuilder(copy: false);
  final header = _Writer(builder);
  header
    ..byte(NbtTagId.compound)
    ..string('');
  _writeCompound(builder, root);
  return builder.toBytes();
}

void _writeCompound(BytesBuilder builder, NbtCompound compound) {
  for (final entry in compound.values.entries) {
    final type = _typeOf(entry.value);
    _Writer(builder)
      ..byte(type)
      ..string(entry.key);
    _writePayload(builder, entry.value);
  }
  builder.addByte(0);
}

void _writePayload(BytesBuilder builder, NbtTag tag) {
  switch (tag) {
    case NbtByte(:final value):
      _Writer(builder).byte(value);
    case NbtShort(:final value):
      _Writer(builder).short(value);
    case NbtInt(:final value):
      _Writer(builder).int32(value);
    case NbtLong(:final value):
      _Writer(builder).long(value);
    case NbtString(:final value):
      _Writer(builder).string(value);
    case NbtCompound():
      _writeCompound(builder, tag);
    case NbtList(:final elementType, :final items):
      _Writer(builder)
        ..byte(elementType)
        ..int32(items.length);
      for (final item in items) {
        _writePayload(builder, item);
      }
  }
}

int _typeOf(NbtTag tag) => switch (tag) {
  NbtByte() => NbtTagId.byte,
  NbtShort() => NbtTagId.short,
  NbtInt() => NbtTagId.int32,
  NbtLong() => NbtTagId.long,
  NbtString() => NbtTagId.string,
  NbtList() => NbtTagId.list,
  NbtCompound() => NbtTagId.compound,
};

class _Writer {
  _Writer(this.builder);

  final BytesBuilder builder;
  final _scratch = ByteData(8);

  void byte(int value) => builder.addByte(value & 0xFF);

  void short(int value) {
    _scratch.setInt16(0, value);
    builder.add(_scratch.buffer.asUint8List(0, 2));
  }

  void int32(int value) {
    _scratch.setInt32(0, value);
    builder.add(_scratch.buffer.asUint8List(0, 4));
  }

  void long(int value) {
    _scratch.setInt64(0, value);
    builder.add(_scratch.buffer.asUint8List(0, 8));
  }

  void string(String value) {
    final bytes = utf8.encode(value);
    short(bytes.length);
    builder.add(bytes);
  }
}
