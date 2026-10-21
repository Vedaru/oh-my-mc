import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/net/mirror.dart';
import 'package:oh_my_mc/core/net/progress.dart';

void main() {
  group('formatBytes', () {
    test('uses 1024-based units', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
    });
  });

  group('formatEta', () {
    test('scales to human units', () {
      expect(formatEta(null), '—');
      expect(formatEta(const Duration(seconds: 4)), '4s');
      expect(formatEta(const Duration(seconds: 80)), '1m 20s');
      expect(formatEta(const Duration(minutes: 75)), '1h 15m');
    });
  });

  group('DownloadProgress', () {
    test('fraction prefers bytes over file count', () {
      const p = DownloadProgress(
        filesDone: 1,
        filesTotal: 2,
        bytesDone: 250,
        bytesTotal: 1000,
      );
      expect(p.fraction, 0.25);
    });

    test('falls back to file count when sizes are unknown', () {
      const p = DownloadProgress(
        filesDone: 3,
        filesTotal: 4,
        bytesDone: 0,
        bytesTotal: 0,
      );
      expect(p.fraction, 0.75);
    });

    test('empty totals do not divide by zero', () {
      expect(DownloadProgress.idle.fraction, 0);
      expect(DownloadProgress.idle.eta, isNull);
    });

    test('eta comes from the measured rate', () {
      const p = DownloadProgress(
        filesDone: 0,
        filesTotal: 1,
        bytesDone: 500,
        bytesTotal: 1500,
        bytesPerSecond: 500,
      );
      expect(p.eta, const Duration(seconds: 2));
    });

    test('no rate means no eta rather than a guess', () {
      const p = DownloadProgress(
        filesDone: 0,
        filesTotal: 1,
        bytesDone: 10,
        bytesTotal: 100,
      );
      expect(p.eta, isNull);
    });
  });

  group('ProgressTracker smoothing', () {
    test('no rate before two samples', () {
      final tracker = ProgressTracker(filesTotal: 1, bytesTotal: 100);
      tracker.addBytes(50);
      expect(tracker.rate, isNull);
    });

    test('rate is bytes over elapsed window', () {
      var now = DateTime(2026);
      final tracker = ProgressTracker(
        filesTotal: 1,
        bytesTotal: 1000,
        clock: () => now,
      );
      tracker.addBytes(100);
      now = now.add(const Duration(seconds: 1));
      tracker.addBytes(200);

      expect(tracker.rate, closeTo(200, 1));
      expect(tracker.snapshot().bytesPerSecond, closeTo(200, 1));
    });

    test('old samples fall out of the window so a stall lowers the rate', () {
      var now = DateTime(2026);
      final tracker = ProgressTracker(
        filesTotal: 1,
        bytesTotal: 100000,
        window: const Duration(seconds: 2),
        clock: () => now,
      );
      tracker.addBytes(1000);
      now = now.add(const Duration(seconds: 1));
      tracker.addBytes(2000);
      now = now.add(const Duration(seconds: 10));
      tracker.addBytes(2100); // only 100 bytes in the last 10 s

      expect(tracker.rate, lessThan(1000));
    });

    test('counts files and exposes the current file name', () {
      final tracker = ProgressTracker(filesTotal: 2, bytesTotal: 10);
      tracker.startFile('a.jar');
      tracker.addBytes(10);
      tracker.completeFile();

      final snap = tracker.snapshot();
      expect(snap.filesDone, 1);
      expect(snap.currentFile, 'a.jar');
      expect(snap.isComplete, isFalse);
    });
  });

  group('mirror classification', () {
    test('recognises the four Mojang host roles', () {
      expect(
        MirrorChain.classify(
          Uri.parse(
            'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json',
          ),
        ),
        EndpointKind.versionManifest,
      );
      expect(
        MirrorChain.classify(
          Uri.parse(
            'https://piston-meta.mojang.com/v1/packages/abc/1.20.1.json',
          ),
        ),
        EndpointKind.versionJson,
      );
      expect(
        MirrorChain.classify(
          Uri.parse(
            'https://libraries.minecraft.net/com/mojang/patchy/2.2.10/patchy-2.2.10.jar',
          ),
        ),
        EndpointKind.library,
      );
      expect(
        MirrorChain.classify(
          Uri.parse('https://resources.download.minecraft.net/00/0008b'),
        ),
        EndpointKind.asset,
      );
      expect(
        MirrorChain.classify(
          Uri.parse('https://piston-data.mojang.com/v1/objects/abc/client.jar'),
        ),
        EndpointKind.gameFile,
      );
    });

    test('legacy launchermeta manifest is recognised', () {
      expect(
        MirrorChain.classify(
          Uri.parse(
            'https://launchermeta.mojang.com/mc/game/version_manifest_v2.json',
          ),
        ),
        EndpointKind.versionManifest,
      );
    });

    test('version json rewrite uses the version id, not the package hash', () {
      final uri = MirrorChain.rewrite(
        Uri.parse(
          'https://piston-meta.mojang.com/v1/packages/61fff13/26.3.json',
        ),
        EndpointKind.versionJson,
        DownloadSource.bmclapi,
      );
      expect(
        uri.toString(),
        'https://bmclapi2.bangbang93.com/version/26.3/json',
      );
    });

    test('library rewrite preserves the maven path', () {
      final uri = MirrorChain.rewrite(
        Uri.parse(
          'https://libraries.minecraft.net/com/mojang/patchy/2.2.10/patchy-2.2.10.jar',
        ),
        EndpointKind.library,
        DownloadSource.bmclapi,
      )!;
      expect(uri.host, 'bmclapi2.bangbang93.com');
      expect(uri.path, '/maven/com/mojang/patchy/2.2.10/patchy-2.2.10.jar');
    });

    test('asset rewrite keeps the two-character prefix', () {
      final uri = MirrorChain.rewrite(
        Uri.parse(
          'https://resources.download.minecraft.net/ab/abcdef0123456789',
        ),
        EndpointKind.asset,
        DownloadSource.bmclapi,
      )!;
      expect(uri.path, '/assets/ab/abcdef0123456789');
    });

    test(
      'piston-data objects are not rewritten (no deterministic mapping)',
      () {
        final official = Uri.parse(
          'https://piston-data.mojang.com/v1/objects/abc/client.jar',
        );
        expect(
          MirrorChain.rewrite(
            official,
            EndpointKind.gameFile,
            DownloadSource.bmclapi,
          ),
          official,
        );
      },
    );

    test('official source is always identity', () {
      final uri = Uri.parse('https://libraries.minecraft.net/a/b.jar');
      expect(
        MirrorChain.rewrite(uri, EndpointKind.library, DownloadSource.official),
        uri,
      );
    });

    test('source attribution distinguishes mirror from official', () {
      expect(
        MirrorChain.sourceOf(
          Uri.parse('https://bmclapi2.bangbang93.com/maven/a/b.jar'),
        ),
        DownloadSource.bmclapi,
      );
      expect(
        MirrorChain.sourceOf(
          Uri.parse('https://libraries.minecraft.net/a/b.jar'),
        ),
        DownloadSource.official,
      );
    });
  });
}
