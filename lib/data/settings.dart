/// App preferences, as stored on disk.
///
/// Deliberately free of Flutter types: the values are persisted as strings, so
/// "what does a corrupt or hand-edited value mean" is a pure function that can be
/// tested without a widget tree. Every unknown value falls back to the default
/// instead of throwing - a launcher that refuses to start because one setting is
/// garbage is worse than one that starts with a default.
library;

import 'dart:convert';

import '../core/instance/memory.dart';

/// Which theme to use. `system` follows the OS.
enum ThemePreference { system, light, dark }

/// The accent colour the whole colour scheme is seeded from.
///
/// An enum, not a colour: this file stays free of Flutter types so the values
/// survive as plain strings, and the palette itself lives in
/// `ui/theme/app_theme.dart`. A stored colour that no longer exists falls back to
/// the default the same way a corrupt `theme` does.
enum AccentChoice { blue, teal, green, orange, red, purple }

/// Which language to use. `system` follows the OS.
///
/// Only two languages ship, so this is an enum rather than a free-form locale
/// list: a `zh_Hant` user should get Simplified Chinese, not English, and an
/// enum makes that fallback decision explicit at the point of use.
enum LanguagePreference { system, english, chinese }

/// An immutable snapshot of everything the app remembers between runs.
class AppSettings {
  const AppSettings({
    this.theme = ThemePreference.system,
    this.language = LanguagePreference.system,
    this.accent = AccentChoice.blue,
    this.playerName = defaultPlayerName,
    this.memoryMb = defaultMemoryMb,
    this.javaDirs = const [],
    this.downloadSource = SourcePreference.auto,
    this.fastestSource,
  });

  /// A valid offline player name (3-16 ASCII word characters). Shown to other
  /// players, so it is user data rather than a localized string.
  static const defaultPlayerName = 'Player';

  /// Heap cap handed to the JVM when an instance does not set its own. 2 GiB is
  /// the smallest value that runs a modern vanilla instance with room to spare,
  /// and low enough not to thrash a 4 GiB machine.
  static const defaultMemoryMb = 2048;

  /// What a first run gets, and what a corrupt store degrades to.
  static const defaults = AppSettings();

  final ThemePreference theme;
  final LanguagePreference language;

  /// Seed for every colour in the app. Motion has no setting of its own any
  /// more: animation is part of the design and only the OS accessibility flag
  /// (OR'd in by `MotionScope`) can turn it off.
  final AccentChoice accent;

  /// Offline profile name. Microsoft sign-in is a later milestone; until then a
  /// launch is always offline, which requires a name and nothing else.
  final String playerName;

  /// Global heap cap, used when an instance has no override.
  final int memoryMb;

  /// Which download source to prefer. `auto` follows the last speed test: the
  /// mirror that won it is tried first, and a failure still falls back to the other.
  final SourcePreference downloadSource;

  /// The source the last speed test ranked first, as a [DownloadSource] id.
  ///
  /// Stored rather than re-measured on every launch: a speed test at startup would
  /// add seconds to opening the launcher for information that changes rarely.
  final String? fastestSource;

  /// Extra directories to look for a JVM in, on top of the built-in roots.
  ///
  /// The launcher downloads its own runtime when a version needs one, but a user
  /// who already keeps JDKs somewhere (a toolchain manager, a second launcher, an
  /// IDE) should not have to download a second copy: pointing at the directory is
  /// enough.
  final List<String> javaDirs;

  /// Persisted form. Keys are stable strings, not enum indices, so reordering an
  /// enum cannot silently reinterpret an existing user's setting.
  Map<String, Object?> toMap() => {
    'theme': theme.name,
    'language': language.name,
    'accent': accent.name,
    'playerName': playerName,
    'memoryMb': memoryMb,
    // A list, so it is stored as JSON in a single string key: the settings store
    // writes scalars, and one key per directory would leak the list's length into
    // the preferences file.
    'javaDirs': jsonEncode(javaDirs),
    'downloadSource': downloadSource.name,
    'fastestSource': ?fastestSource,
  };

  /// Reads [map], falling back to [defaults] per field rather than wholesale, so
  /// one bad key does not discard the others.
  factory AppSettings.fromMap(Map<String, Object?> map) {
    return AppSettings(
      theme: _enumByName(
        ThemePreference.values,
        map['theme'],
        ThemePreference.system,
      ),
      language: _enumByName(
        LanguagePreference.values,
        map['language'],
        LanguagePreference.system,
      ),
      accent: _enumByName(
        AccentChoice.values,
        map['accent'],
        AccentChoice.blue,
      ),
      // A blank or implausible name would make the game refuse to start or,
      // worse, start with an empty name; clamp it back to the default instead.
      playerName: _validPlayerName(map['playerName']),
      memoryMb: _validMemoryMb(map['memoryMb']),
      javaDirs: _validJavaDirs(map['javaDirs']),
      downloadSource: _enumByName(
        SourcePreference.values,
        map['downloadSource'],
        SourcePreference.auto,
      ),
      fastestSource: switch (map['fastestSource']) {
        'official' => 'official',
        'bmclapi' => 'bmclapi',
        _ => null,
      },
    );
  }

  AppSettings copyWith({
    ThemePreference? theme,
    LanguagePreference? language,
    AccentChoice? accent,
    String? playerName,
    int? memoryMb,
    List<String>? javaDirs,
    SourcePreference? downloadSource,
    String? fastestSource,
  }) => AppSettings(
    theme: theme ?? this.theme,
    language: language ?? this.language,
    accent: accent ?? this.accent,
    playerName: playerName ?? this.playerName,
    memoryMb: memoryMb ?? this.memoryMb,
    javaDirs: javaDirs ?? this.javaDirs,
    downloadSource: downloadSource ?? this.downloadSource,
    fastestSource: fastestSource ?? this.fastestSource,
  );

  /// Equality is derived from [toMap], not hand-written.
  ///
  /// A hand-written `==` is how this class shipped a real bug: `downloadSource` was
  /// added to the model and the settings page, but not to `==` - so Riverpod compared
  /// the old and new state, saw no difference, and never rebuilt. The radio buttons
  /// held the new value and showed the old one, which reads to a user as "the control
  /// does not work". Deriving equality from the persisted form means a new field
  /// participates as soon as it is stored.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings && _sameMap(toMap(), other.toMap());

  @override
  int get hashCode => Object.hashAll(
    toMap().entries.map((entry) => Object.hash(entry.key, entry.value)),
  );

  @override
  String toString() =>
      'AppSettings(theme: ${theme.name}, language: ${language.name}, '
      'accent: ${accent.name}, playerName: $playerName, '
      'memoryMb: $memoryMb, javaDirs: $javaDirs)';
}

/// Minecraft accepts 3-16 characters from `[A-Za-z0-9_]`. Anything else is a
/// hand-edited or older file, and the default is safer than passing it to the
/// game.
String _validPlayerName(Object? raw) {
  if (raw is! String) return AppSettings.defaultPlayerName;
  return RegExp(r'^[A-Za-z0-9_]{3,16}$').hasMatch(raw)
      ? raw
      : AppSettings.defaultPlayerName;
}

/// Out-of-range values fall back to the default rather than clamping: a stored
/// `0` or `999999` is corruption, and silently turning it into 512 or 65536 would
/// launch a game on a heap the user never chose. The range itself lives in
/// [kMinMemoryMb]/[kMaxMemoryMb] so the sliders cannot drift from it.
int _validMemoryMb(Object? raw) {
  // The preferences file stores every value as a string (see `PrefsSettingsStore`), so
  // accepting only an `int` here meant the heap reset to the default on every launch.
  final value = switch (raw) {
    int value => value,
    String value => int.tryParse(value.trim()),
    _ => null,
  };
  if (value == null || value < kMinMemoryMb || value > kMaxMemoryMb) {
    return AppSettings.defaultMemoryMb;
  }
  return value;
}

/// Reads the JSON-encoded directory list. Anything unreadable is an empty list:
/// losing the extra search paths costs a rescan, not a crash.
List<String> _validJavaDirs(Object? raw) {
  if (raw is! String || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final entry in decoded)
        if (entry is String && entry.trim().isNotEmpty) entry,
    ];
  } on FormatException {
    return const [];
  }
}

bool _sameMap(Map<String, Object?> a, Map<String, Object?> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key)) return false;
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return fallback;
}

/// Where settings live.
///
/// An interface so tests can use [MemorySettingsStore] and never touch a platform
/// plugin: `shared_preferences` needs a real host, and mocking its channel would
/// test the mock rather than the app's composition.
abstract interface class SettingsStore {
  /// The current values. Synchronous because `main` awaits [init] before the
  /// first frame, so there is no window where this is unknown.
  AppSettings get current;

  /// Loads from the backing store once, before `runApp`.
  Future<void> init();

  /// Persists [settings]. Implementations report failures rather than throwing:
  /// losing a preference must not take the app down.
  Future<void> write(AppSettings settings);
}

/// In-memory store for tests and for a session where persistence is unavailable
/// (e.g. a read-only profile directory).
class MemorySettingsStore implements SettingsStore {
  MemorySettingsStore([this._settings = AppSettings.defaults]);

  AppSettings _settings;
  int writes = 0;

  @override
  AppSettings get current => _settings;

  @override
  Future<void> init() async {}

  @override
  Future<void> write(AppSettings settings) async {
    _settings = settings;
    writes++;
  }
}

/// Which CDN the launcher prefers for Mojang files.
///
/// `auto` is not "no preference": it means "the source the last speed test ranked
/// first". A launcher that always ships with the same default is the reason installs
/// crawl for users whose link to the official CDN is the slow one.
enum SourcePreference {
  auto('auto'),
  official('official'),
  bmclapi('bmclapi');

  const SourcePreference(this.id);

  final String id;
}
