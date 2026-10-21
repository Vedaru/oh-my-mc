/// App preferences, as stored on disk.
///
/// Deliberately free of Flutter types: the values are persisted as strings, so
/// "what does a corrupt or hand-edited value mean" is a pure function that can be
/// tested without a widget tree. Every unknown value falls back to the default
/// instead of throwing - a launcher that refuses to start because one setting is
/// garbage is worse than one that starts with a default.
library;

/// Which theme to use. `system` follows the OS.
enum ThemePreference { system, light, dark }

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
    this.uiAnimations = true,
  });

  /// What a first run gets, and what a corrupt store degrades to.
  static const defaults = AppSettings();

  final ThemePreference theme;
  final LanguagePreference language;

  /// The app's own switch. The OS accessibility setting is OR'd on top of this
  /// by `MotionScope`, so this can only ever turn motion *off*, never on.
  final bool uiAnimations;

  /// Persisted form. Keys are stable strings, not enum indices, so reordering an
  /// enum cannot silently reinterpret an existing user's setting.
  Map<String, Object?> toMap() => {
    'theme': theme.name,
    'language': language.name,
    'uiAnimations': uiAnimations,
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
      uiAnimations: switch (map['uiAnimations']) {
        true => true,
        false => false,
        _ => true,
      },
    );
  }

  AppSettings copyWith({
    ThemePreference? theme,
    LanguagePreference? language,
    bool? uiAnimations,
  }) => AppSettings(
    theme: theme ?? this.theme,
    language: language ?? this.language,
    uiAnimations: uiAnimations ?? this.uiAnimations,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          other.theme == theme &&
          other.language == language &&
          other.uiAnimations == uiAnimations;

  @override
  int get hashCode => Object.hash(theme, language, uiAnimations);

  @override
  String toString() =>
      'AppSettings(theme: ${theme.name}, language: ${language.name}, '
      'uiAnimations: $uiAnimations)';
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
