import 'package:shared_preferences/shared_preferences.dart';

import 'settings.dart';

/// [SettingsStore] over `shared_preferences`.
///
/// Every key is namespaced: the app shares a preferences file with whatever the
/// Flutter tooling writes, and an unprefixed `theme` is the kind of key that
/// collides silently and is then very hard to explain.
class PrefsSettingsStore implements SettingsStore {
  PrefsSettingsStore({this.onWriteError});

  static const _prefix = 'ohmy.setting.';

  final void Function(Object error, StackTrace stack)? onWriteError;

  AppSettings _settings = AppSettings.defaults;
  SharedPreferences? _prefs;

  @override
  AppSettings get current => _settings;

  @override
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      final raw = <String, Object?>{
        for (final key in ['theme', 'language', 'uiAnimations'])
          key: prefs.get('$_prefix$key'),
      };
      _settings = AppSettings.fromMap(raw);
    } on Object catch (error, stack) {
      // A missing or unreadable store is not fatal: the app runs on defaults and
      // simply will not remember this session.
      onWriteError?.call(error, stack);
      _settings = AppSettings.defaults;
    }
  }

  @override
  Future<void> write(AppSettings settings) async {
    _settings = settings;
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      for (final entry in settings.toMap().entries) {
        final key = '$_prefix${entry.key}';
        final value = entry.value;
        if (value is bool) {
          await prefs.setBool(key, value);
        } else if (value != null) {
          await prefs.setString(key, value.toString());
        }
      }
    } on Object catch (error, stack) {
      onWriteError?.call(error, stack);
    }
  }
}
