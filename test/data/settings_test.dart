import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/app/providers.dart';
import 'package:oh_my_mc/data/settings.dart';

void main() {
  group('AppSettings serialization', () {
    test('round-trips every value', () {
      for (final theme in ThemePreference.values) {
        for (final language in LanguagePreference.values) {
          for (final accent in AccentChoice.values) {
            final original = AppSettings(
              theme: theme,
              language: language,
              accent: accent,
            );
            expect(
              AppSettings.fromMap(original.toMap()),
              original,
              reason: 'failed for $original',
            );
          }
        }
      }
    });

    test('an empty map is the default', () {
      expect(AppSettings.fromMap(const {}), AppSettings.defaults);
    });

    test('a garbage value falls back per field, not wholesale', () {
      final settings = AppSettings.fromMap(const {
        'theme': 'chartreuse',
        'language': 'klingon',
        'accent': 'chartreuse',
      });
      expect(settings, AppSettings.defaults);
    });

    test('a partly valid map keeps the valid half', () {
      // The interesting case: one corrupt key must not discard the good ones.
      final settings = AppSettings.fromMap(const {
        'theme': 'dark',
        'language': 'not-a-language',
      });
      expect(settings.theme, ThemePreference.dark);
      expect(settings.language, LanguagePreference.system);
    });

    test('stored keys are names, so reordering an enum is safe', () {
      // Indices would silently reinterpret an existing user's setting if the
      // enum were reordered; names cannot.
      final map = const AppSettings(
        theme: ThemePreference.dark,
        language: LanguagePreference.chinese,
      ).toMap();
      expect(map['theme'], 'dark');
      expect(map['language'], 'chinese');
    });

    test('the accent defaults to blue', () {
      expect(AppSettings.defaults.accent, AccentChoice.blue);
    });
  });

  group('settings store', () {
    test('memory store starts at defaults and records writes', () async {
      final store = MemorySettingsStore();
      await store.init();
      expect(store.current, AppSettings.defaults);

      const next = AppSettings(accent: AccentChoice.teal);
      await store.write(next);
      expect(store.current, next);
      expect(store.writes, 1);
    });

    test('memory store honours a supplied initial value', () async {
      final store = MemorySettingsStore(
        const AppSettings(theme: ThemePreference.light),
      );
      await store.init();
      expect(store.current.theme, ThemePreference.light);
    });
  });

  group('AppSettingsNotifier', () {
    Future<ProviderContainer> containerWith(SettingsStore store) async {
      await store.init();
      final container = ProviderContainer(
        overrides: [settingsStoreProvider.overrideWith((ref) => store)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('builds from the store, not from defaults', () async {
      final container = await containerWith(
        MemorySettingsStore(
          const AppSettings(language: LanguagePreference.chinese),
        ),
      );

      expect(
        container.read(appSettingsProvider).language,
        LanguagePreference.chinese,
      );
    });

    test(
      'a write reaches the store, so the change survives a relaunch',
      () async {
        final store = MemorySettingsStore();
        final container = await containerWith(store);

        await container
            .read(appSettingsProvider.notifier)
            .setAccent(AccentChoice.purple);

        expect(container.read(appSettingsProvider).accent, AccentChoice.purple);
        expect(
          store.current.accent,
          AccentChoice.purple,
          reason: 'a change that is not written is lost on the next launch',
        );
      },
    );

    test('each setter touches only its own field', () async {
      final container = await containerWith(MemorySettingsStore());

      await container
          .read(appSettingsProvider.notifier)
          .setTheme(ThemePreference.dark);
      await container
          .read(appSettingsProvider.notifier)
          .setLanguage(LanguagePreference.english);

      final settings = container.read(appSettingsProvider);
      expect(settings.theme, ThemePreference.dark);
      expect(settings.language, LanguagePreference.english);
      expect(settings.accent, AccentChoice.blue);
    });
  });
}
