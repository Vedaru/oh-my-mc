import 'dart:io';

/// `options.txt`, as the game writes it.
///
/// One `key:value` per line, order preserved, values opaque strings. The launcher
/// only needs three things from it: read the enabled resource packs, write them
/// back, and never lose a line it did not understand - the game owns that file and
/// rewrites it on exit, so a launcher that rewrites it wholesale loses settings.
class OptionsTxt {
  OptionsTxt._(this._lines);

  final List<String> _lines;

  static OptionsTxt parse(String text) =>
      OptionsTxt._(text.isEmpty ? <String>[] : text.split('\n'));

  static Future<OptionsTxt> read(File file) async {
    if (!await file.exists()) return OptionsTxt._(<String>[]);
    try {
      return parse(await file.readAsString());
    } on FileSystemException {
      return OptionsTxt._(<String>[]);
    }
  }

  String get text => _lines.join('\n');

  /// The value of [key], or null when the option is absent.
  String? operator [](String key) {
    final prefix = '$key:';
    for (final line in _lines) {
      if (line.startsWith(prefix)) return line.substring(prefix.length);
    }
    return null;
  }

  /// `resourcePacks:["vanilla","file/pack.zip","file/other.zip"]`
  ///
  /// The value is a JSON-ish array of double-quoted strings. Mods and users write
  /// hand-edited files, so an unparseable value reads as empty rather than throwing:
  /// the worst case is a pack shown as disabled, which one click fixes.
  List<String> get resourcePacks {
    final raw = this['resourcePacks'];
    if (raw == null) return const ['vanilla'];
    final quoted = RegExp(r'"((?:[^"\\]|\\.)*)"').allMatches(raw);
    final packs = [for (final match in quoted) _unescape(match.group(1)!)];
    return packs.isEmpty ? const ['vanilla'] : packs;
  }

  /// `\"` and `\\` are the only escapes the game writes inside the list.
  /// `\\` and `\"` are the only escapes the game writes inside the list: a
  /// backslash escapes the next character, so one pass unwinds them.
  static String _unescape(String value) {
    final out = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      final char = value[i];
      if (char == '\\' && i + 1 < value.length) {
        out.write(value[++i]);
      } else {
        out.write(char);
      }
    }
    return out.toString();
  }

  /// Writes the pack list back, keeping `vanilla` first as the game does.
  void setResourcePacks(List<String> packs) {
    final ordered = [
      'vanilla',
      for (final pack in packs)
        if (pack != 'vanilla') pack,
    ];
    final value =
        '[${ordered.map((p) => '"${p.replaceAll('"', r'\"')}"').join(',')}]';
    _set('resourcePacks', value);
  }

  /// Sets one key, replacing the first occurrence and keeping its position.
  void _set(String key, String value) {
    final prefix = '$key:';
    for (var i = 0; i < _lines.length; i++) {
      if (_lines[i].startsWith(prefix)) {
        _lines[i] = '$prefix$value';
        return;
      }
    }
    // Trailing newline from the last line: keep the file ending the way the game
    // writes it.
    if (_lines.isNotEmpty && _lines.last.isEmpty) {
      _lines.insert(_lines.length - 1, '$prefix$value');
    } else {
      _lines.add('$prefix$value');
    }
  }
}

/// The pack id the game uses inside `options.txt` for a pack file or folder.
///
/// `resourcepacks/My Pack.zip` → `file/My Pack.zip`; a directory keeps its name.
/// The game uses `file/` for both, which is why a launcher cannot tell them apart
/// from the option value alone.
String packIdFor(String entryName) => 'file/$entryName';

/// The entry name from a pack id, or null when it is not a file-backed pack.
String? packEntryName(String packId) =>
    packId.startsWith('file/') ? packId.substring('file/'.length) : null;
