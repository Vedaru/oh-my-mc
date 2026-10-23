import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/data/prefs_settings_store.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings must survive a restart. The store writes every field; the bug this pins is
/// that `init` read three of them back, so memory, player name, Java directories and
/// the download source silently reset on every launch while the file still held them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every field written is read back', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PrefsSettingsStore();
    await store.init();

    const written = AppSettings(
      theme: ThemePreference.light,
      language: LanguagePreference.chinese,
      accent: AccentChoice.teal,
      playerName: 'Steve',
      memoryMb: 6144,
      javaDirs: ['/opt/java/17'],
      downloadSource: SourcePreference.bmclapi,
      fastestSource: 'bmclapi',
    );
    await store.write(written);

    final reopened = PrefsSettingsStore();
    await reopened.init();
    // Field-by-field, so a mismatch names itself instead of printing two long records.
    for (final entry in written.toMap().entries) {
      expect(
        reopened.current.toMap()[entry.key],
        entry.value,
        reason: entry.key,
      );
    }
    expect(reopened.current, written);
  });

  test('the language can be set back to system and stays system', () async {
    SharedPreferences.setMockInitialValues({
      'ohmy.setting.language': 'english',
    });
    final store = PrefsSettingsStore();
    await store.init();
    expect(store.current.language, LanguagePreference.english);

    await store.write(
      store.current.copyWith(language: LanguagePreference.system),
    );

    final reopened = PrefsSettingsStore();
    await reopened.init();
    expect(reopened.current.language, LanguagePreference.system);
  });
}
