import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/net/mirror.dart';
import 'package:oh_my_mc/data/mirror_preference.dart';
import 'package:oh_my_mc/data/settings.dart';

void main() {
  group('mirror order', () {
    test('a pinned source goes first and the other stays as fallback', () {
      expect(mirrorOrderFor(SourcePreference.bmclapi), [
        DownloadSource.bmclapi,
        DownloadSource.official,
      ]);
      expect(mirrorOrderFor(SourcePreference.official), [
        DownloadSource.official,
        DownloadSource.bmclapi,
      ]);
    });

    test('auto follows the measured winner', () {
      expect(
        mirrorOrderFor(
          SourcePreference.auto,
          measuredFastest: DownloadSource.bmclapi,
        ).first,
        DownloadSource.bmclapi,
      );
      expect(
        mirrorOrderFor(
          SourcePreference.auto,
          measuredFastest: DownloadSource.official,
        ).first,
        DownloadSource.official,
      );
    });

    test('auto with no measurement is official-first', () {
      expect(
        mirrorOrderFor(SourcePreference.auto).first,
        DownloadSource.official,
      );
    });

    test('the loser is never dropped: a preference is a hint, not a lock', () {
      for (final preference in SourcePreference.values) {
        expect(mirrorOrderFor(preference), hasLength(2));
      }
    });

    test('speed samples map onto sources by name', () {
      expect(sourceOfMirrorSample('Mojang'), DownloadSource.official);
      expect(sourceOfMirrorSample('BMCLAPI'), DownloadSource.bmclapi);
      // A sample from a CDN that is not switchable has no source.
      expect(sourceOfMirrorSample('Modrinth'), isNull);
    });
  });

  group('settings', () {
    test('the source preference and the measurement round-trip', () {
      const settings = AppSettings(
        downloadSource: SourcePreference.bmclapi,
        fastestSource: 'bmclapi',
      );

      final restored = AppSettings.fromMap(settings.toMap());

      expect(restored.downloadSource, SourcePreference.bmclapi);
      expect(restored.fastestSource, 'bmclapi');
      expect(restored, settings);
    });

    test('an unknown or missing value falls back to auto', () {
      final restored = AppSettings.fromMap({
        'downloadSource': 'carrier-pigeon',
      });

      expect(restored.downloadSource, SourcePreference.auto);
      expect(restored.fastestSource, isNull);
    });
  });
}
