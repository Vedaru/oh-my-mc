import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/l10n/l10n.dart';

/// Reads an ARB file as a map of message key -> value, skipping `@@` metadata and
/// `@key` descriptions.
Map<String, String> _messages(String path) {
  final raw =
      json.decode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final entry in raw.entries)
      if (!entry.key.startsWith('@')) entry.key: entry.value as String,
  };
}

/// Removes `///` and `//` comments, so prose explaining why a type is avoided
/// does not count as using it.
String _stripComments(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//.*'), '');

void main() {
  group('ARB parity', () {
    // A missing zh key does not throw at runtime: gen-l10n leaves the English
    // text in the zh class, so the UI silently shows English. Its warning is easy
    // to miss in a build log, so the suite enforces it as a hard fail.
    test('en and zh define exactly the same keys', () {
      final en = _messages('lib/l10n/app_en.arb');
      final zh = _messages('lib/l10n/app_zh.arb');

      expect(
        zh.keys.toSet().difference(en.keys.toSet()),
        isEmpty,
        reason: 'zh defines keys that en (the template) does not',
      );
      expect(
        en.keys.toSet().difference(zh.keys.toSet()),
        isEmpty,
        reason: 'zh is missing these keys, so they would render in English',
      );
    });

    test('zh actually differs from en where a translation is expected', () {
      final en = _messages('lib/l10n/app_en.arb');
      final zh = _messages('lib/l10n/app_zh.arb');

      // Anything byte-identical is either a forgotten translation or a word that
      // is genuinely the same in both languages, and each must be listed here -
      // so an untranslated string fails until someone makes that decision.
      const identicalByDesign = {
        'appTitle', // product name
        'setupJava', // "Java" is "Java" in Chinese
        'instanceJavaLabel', // same
        'instanceMemoryMb', // a number and the SI-ish unit "MB"
        'languageEnglish', // a language is named in its own language
      };
      final untranslated = [
        for (final key in en.keys)
          if (en[key] == zh[key] && !identicalByDesign.contains(key)) key,
      ];

      expect(
        untranslated,
        isEmpty,
        reason: 'these zh strings are still the English text',
      );
    });

    test('every en message has a description for translators', () {
      final raw =
          json.decode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map;
      final missing = [
        for (final key in raw.keys)
          if (!key.startsWith('@') &&
              !((raw['@$key'] as Map?)?.containsKey('description') ?? false))
            key,
      ];
      expect(missing, isEmpty);
    });
  });

  group('locale resolution', () {
    test('en and zh are supported; zh_Hans falls back to zh', () async {
      expect(AppLocalizations.supportedLocales, contains(const Locale('en')));
      expect(AppLocalizations.supportedLocales, contains(const Locale('zh')));

      // PCL's users are majority Simplified Chinese and Windows reports
      // zh_Hans_CN. Without this the app would open in English.
      final zhHans = await AppLocalizations.delegate.load(
        const Locale('zh', 'CN'),
      );
      expect(zhHans.navLaunch, '启动');
    });

    test('an unsupported locale is not claimed by the delegate', () {
      expect(
        AppLocalizations.delegate.isSupported(const Locale('fr')),
        isFalse,
      );
    });
  });

  group('delegate tree', () {
    // The generated file names the SDK Material/Cupertino delegates in its
    // `localizationsDelegates` list. We use our own list instead, and this guards
    // the reason: an unprefixed reference resolves to the in-SDK Material copy,
    // a second type system from the `material_ui` package the app actually uses.
    // A qualified `m3.` reference is the correct one and is allowed.
    test('our own code never references the SDK Material localization types', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.contains('lib/l10n/generated/')) continue;
        final source = _stripComments(entity.readAsStringSync());
        for (final banned in [
          RegExp(r'(?<!\.)GlobalMaterialLocalizations'),
          RegExp(r'(?<!\.)GlobalCupertinoLocalizations'),
        ]) {
          if (banned.hasMatch(source)) {
            offenders.add('${entity.path}: ${banned.pattern}');
          }
        }
        if (source.contains('AppLocalizations.localizationsDelegates')) {
          offenders.add('${entity.path}: AppLocalizations.localizationsDelegates');
        }
      }
      expect(offenders, isEmpty);
    });

    test('the shipped delegate list has one entry per tree', () {
      // Our own delegate plus every delegate `material_ui` needs. Counting them
      // instead of hardcoding 3 means an upstream change to the plural list is
      // not mistaken for a wiring bug here.
      expect(
        appLocalizationsDelegates,
        hasLength(1 + m3.GlobalMaterialLocalizations.delegates.length),
      );
      expect(appLocalizationsDelegates, contains(AppLocalizations.delegate));
    });
  });
}
