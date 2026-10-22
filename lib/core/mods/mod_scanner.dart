import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'zip_entry_reader.dart';

/// Which mod loader a jar was built for.
///
/// Not a label for show: the metadata file each loader uses is different, so this
/// is how the scanner knows what it just read - and it tells the user why a mod
/// will not load ("this is a Forge jar, the instance is Fabric").
enum ModLoaderKind {
  fabric('Fabric'),
  quilt('Quilt'),
  forge('Forge'),
  neoforge('NeoForge'),
  legacyForge('Forge (1.12-)'),
  unknown('Unknown');

  const ModLoaderKind(this.label);

  final String label;
}

/// One jar (or disabled jar) in `mods/`.
class ModEntry {
  const ModEntry({
    required this.path,
    required this.enabled,
    required this.sizeBytes,
    required this.loader,
    this.id,
    this.name,
    this.version,
    this.authors,
    this.problem,
  });

  /// Absolute path on disk.
  final String path;

  /// `.jar` is enabled, `.jar.disabled` is not. That suffix is the convention
  /// every launcher uses, which is why enabling is a rename rather than a
  /// separate list of enabled ids.
  final bool enabled;

  final int sizeBytes;
  final ModLoaderKind loader;

  /// The mod's own id (`fabric.mod.json`'s `id`, `mods.toml`'s `modId`).
  final String? id;
  final String? name;
  final String? version;
  final String? authors;

  /// Why the metadata could not be read - a corrupt jar, or a jar-shaped file
  /// that is not a mod. Shown instead of hiding the file: a user who dragged the
  /// wrong file in needs to see it.
  final String? problem;

  String get fileName => p.basename(path);

  /// What to show as the row's title: the mod's own name, else the file name.
  String get displayName =>
      (name?.trim().isNotEmpty ?? false) ? name! : fileName;
}

/// The disabled-file suffix. Public because the UI explains it: "rename to
/// `.jar.disabled`" is a thing users do by hand in other launchers.
const disabledSuffix = '.disabled';

/// Reads every mod in [modsDir], enabled and disabled, sorted by display name.
///
/// A missing directory is an empty list: a fresh instance has no `mods/`, and that
/// is not an error.
Future<List<ModEntry>> scanMods(String modsDir) async {
  final dir = Directory(modsDir);
  if (!await dir.exists()) return const [];

  final entries = <ModEntry>[];
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    if (!isModFileName(name)) continue;
    entries.add(await readMod(entity.path));
  }
  entries.sort(
    (a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
  );
  return entries;
}

String _text(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);

/// `foo.jar` and `foo.jar.disabled` are mods; `foo.zip` is not.
bool isModFileName(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.jar') || lower.endsWith('.jar$disabledSuffix');
}

/// Reads one mod jar's metadata.
///
/// Failures are reported in [ModEntry.problem] rather than thrown: one corrupt
/// jar must not blank the whole list, and the row still has to be there so the
/// user can delete it.
Future<ModEntry> readMod(String path) async {
  final file = File(path);
  final size = await file.length();
  final enabled = !path.toLowerCase().endsWith(disabledSuffix);

  ModEntry unreadable(String problem) => ModEntry(
    path: path,
    enabled: enabled,
    sizeBytes: size,
    loader: ModLoaderKind.unknown,
    problem: problem,
  );

  // A zip starts with "PK". Four bytes, and it distinguishes "not a jar" from "a
  // jar with no metadata" - two very different things for the user.
  try {
    final signature = await file.openRead(0, 4).first;
    if (signature.length < 4 || signature[0] != 0x50 || signature[1] != 0x4b) {
      return unreadable('not a jar (no zip signature)');
    }
  } on FileSystemException catch (e) {
    return unreadable('could not read the file (${e.osError?.message ?? e})');
  }

  ZipEntryReader reader;
  try {
    reader = await ZipEntryReader.open(file);
  } on FileSystemException catch (e) {
    return unreadable('could not open the jar (${e.osError?.message ?? e})');
  }

  try {
    // The descriptors, most specific first: a Quilt mod may also ship
    // `fabric.mod.json`, and Forge's newer file can coexist with the older one.
    final quilt = await reader.read('quilt.mod.json');
    if (quilt != null) {
      return _fromQuilt(path, size, enabled, _text(quilt));
    }
    final fabric = await reader.read('fabric.mod.json');
    if (fabric != null) {
      return _fromFabric(path, size, enabled, _text(fabric));
    }
    final neo = await reader.read('META-INF/neoforge.mods.toml');
    if (neo != null) {
      return _fromToml(path, size, enabled, _text(neo), ModLoaderKind.neoforge);
    }
    final forge = await reader.read('META-INF/mods.toml');
    if (forge != null) {
      return _fromToml(path, size, enabled, _text(forge), ModLoaderKind.forge);
    }
    final legacy = await reader.read('mcmod.info');
    if (legacy != null) {
      return _fromLegacy(path, size, enabled, _text(legacy));
    }
  } on Object catch (e) {
    // A truncated or hand-edited zip: reported on the row, not thrown.
    return unreadable('unreadable jar ($e)');
  } finally {
    await reader.close();
  }

  // A jar with none of the descriptors: a library shipped inside `mods/`, or a mod
  // whose metadata lives elsewhere. Named, not hidden.
  return unreadable('no mod metadata in the jar');
}

ModEntry _fromFabric(String path, int size, bool enabled, String json) {
  try {
    final data = jsonDecode(json);
    if (data is! Map) throw const FormatException('not an object');
    return ModEntry(
      path: path,
      enabled: enabled,
      sizeBytes: size,
      loader: ModLoaderKind.fabric,
      id: _string(data['id']),
      name: _string(data['name']) ?? _string(data['id']),
      version: _string(data['version']),
      authors: _people(data['authors']),
    );
  } on Object catch (e) {
    return _broken(path, size, enabled, ModLoaderKind.fabric, e);
  }
}

ModEntry _fromQuilt(String path, int size, bool enabled, String json) {
  try {
    final data = jsonDecode(json);
    final loader = data is Map ? data['quilt_loader'] : null;
    if (loader is! Map) throw const FormatException('no quilt_loader');
    final metadata = loader['metadata'];
    return ModEntry(
      path: path,
      enabled: enabled,
      sizeBytes: size,
      loader: ModLoaderKind.quilt,
      id: _string(loader['id']),
      name: metadata is Map ? _string(metadata['name']) : null,
      version: _string(loader['version']),
      authors: metadata is Map ? _people(metadata['contributors']) : null,
    );
  } on Object catch (e) {
    return _broken(path, size, enabled, ModLoaderKind.quilt, e);
  }
}

/// `mods.toml`, parsed with a regex rather than a TOML parser.
///
/// Only three keys matter and they are always `key = "value"` at the top of the
/// first `[[mods]]` table; a general TOML parser would be a new dependency for
/// three strings that never nest in practice.
ModEntry _fromToml(
  String path,
  int size,
  bool enabled,
  String toml,
  ModLoaderKind loader,
) {
  final block = _firstModsBlock(toml);
  final id = _tomlValue(block, 'modId');
  final name = _tomlValue(block, 'displayName');
  final version = _tomlValue(block, 'version');
  return ModEntry(
    path: path,
    enabled: enabled,
    sizeBytes: size,
    loader: loader,
    id: id,
    name: name == null || name.isEmpty ? id : name,
    // `${file.jarVersion}` is a literal placeholder Forge fills in at load time;
    // showing it verbatim in a list is noise.
    version: version == null || version.contains(r'${') ? null : version,
    authors: _tomlValue(block, 'authors'),
  );
}

String _firstModsBlock(String toml) {
  final start = toml.indexOf('[[mods]]');
  if (start < 0) return toml;
  final next = toml.indexOf('[[', start + 1);
  return next < 0 ? toml.substring(start) : toml.substring(start, next);
}

String? _tomlValue(String block, String key) {
  final match = RegExp(
    '^\\s*$key\\s*=\\s*"([^"]*)"',
    multiLine: true,
  ).firstMatch(block);
  return match?.group(1);
}

ModEntry _fromLegacy(String path, int size, bool enabled, String json) {
  try {
    final data = jsonDecode(json);
    final first = data is List && data.isNotEmpty ? data.first : null;
    if (first is! Map) throw const FormatException('empty mcmod.info');
    return ModEntry(
      path: path,
      enabled: enabled,
      sizeBytes: size,
      loader: ModLoaderKind.legacyForge,
      id: _string(first['modid']),
      name: _string(first['name']),
      version: _string(first['version']),
      authors: _people(first['authorList']) ?? _string(first['author']),
    );
  } on Object catch (e) {
    return _broken(path, size, enabled, ModLoaderKind.legacyForge, e);
  }
}

ModEntry _broken(
  String path,
  int size,
  bool enabled,
  ModLoaderKind kind,
  Object e,
) => ModEntry(
  path: path,
  enabled: enabled,
  sizeBytes: size,
  loader: kind,
  problem: 'unreadable metadata ($e)',
);

String? _string(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

/// `authors` is a list of strings in Fabric, a list of objects with `name` in
/// Quilt, and a plain string in `mcmod.info`.
String? _people(Object? value) {
  if (value is String) return _string(value);
  if (value is! List) return null;
  final names = <String>[
    for (final entry in value)
      if (entry is String)
        entry
      else if (entry is Map && _string(entry['name']) != null)
        _string(entry['name'])!,
  ];
  return names.isEmpty ? null : names.join(', ');
}

/// Renames a mod between enabled and disabled.
///
/// Renaming is the whole mechanism: the loader only scans `*.jar`, so the file
/// stays where it is and nothing has to be remembered in a database. Returns the
/// new path.
Future<String> setModEnabled(ModEntry mod, bool enabled) async {
  if (mod.enabled == enabled) return mod.path;
  final target = enabled
      ? mod.path.substring(0, mod.path.length - disabledSuffix.length)
      : '${mod.path}$disabledSuffix';

  if (File(target).existsSync()) {
    throw FileSystemException(
      'both ${p.basename(mod.path)} and ${p.basename(target)} exist',
      target,
    );
  }
  await File(mod.path).rename(target);
  return target;
}

/// Deletes a mod jar.
///
/// Deliberately not a trash implementation: Dart has no portable trash API, and a
/// half-working one (a directory only this launcher can restore from) is worse
/// than a confirmation dialog. The caller asks first.
Future<void> deleteMod(ModEntry mod) async {
  final file = File(mod.path);
  if (!await file.exists()) return;
  await file.delete();
}
