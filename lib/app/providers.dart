import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings.dart';

/// The settings store, injected at startup so tests can substitute
/// [MemorySettingsStore] and never touch a platform plugin.
final settingsStoreProvider = Provider<SettingsStore>(
  (ref) =>
      throw StateError('settingsStoreProvider must be overridden at startup'),
);

/// The live settings. Reading this rebuilds the app root, which is how a change
/// on `/setup` reaches the theme, the locale and `MotionScope` at once.
///
/// Writes go through [AppSettingsNotifier.set] so persistence and the in-memory
/// value cannot disagree: the notifier holds the store, not the other way round.
class AppSettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(settingsStoreProvider).current;

  SettingsStore get _store => ref.read(settingsStoreProvider);

  /// Applies [settings] immediately, then persists. Persisting first would make
  /// the UI lag a disk write behind the user's click.
  Future<void> set(AppSettings settings) async {
    state = settings;
    await _store.write(settings);
  }

  Future<void> setTheme(ThemePreference theme) =>
      set(state.copyWith(theme: theme));

  Future<void> setLanguage(LanguagePreference language) =>
      set(state.copyWith(language: language));

  Future<void> setAccent(AccentChoice accent) =>
      set(state.copyWith(accent: accent));

  /// How strong the wash over the wallpaper is.
  Future<void> setBackgroundDim(double dim) =>
      set(state.copyWith(backgroundDim: dim));

  /// Null clears the wallpaper.
  Future<void> setBackground(String? path) =>
      set(state.copyWith(backgroundPath: path, clearBackground: path == null));
}

final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);

/// Just the global heap cap, so a widget that only shows "the default is N"
/// does not rebuild when the theme changes.
final appSettingsMemoryProvider = Provider<int>(
  (ref) => ref.watch(appSettingsProvider.select((s) => s.memoryMb)),
);
