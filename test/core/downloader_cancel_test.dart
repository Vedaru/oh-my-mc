import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/net/cancellation.dart';
import 'package:oh_my_mc/core/net/downloader.dart';
import 'package:oh_my_mc/core/net/mirror.dart';
import 'package:path/path.dart' as p;

import '../support/mini_world.dart';

/// Cancelling an install used to hang: a socket that had sent headers but no
/// body leaves the downloader parked in `await for`, and the cancel flag was
/// only read per chunk. Worse, a `CancelledException` raised inside the mirror
/// loop was collected as a *source failure* and retried, so "stop" produced
/// two more attempts before surfacing as a `DownloadFailedException`.
void main() {
  late MiniWorld world;
  late Directory temp;

  setUp(() async {
    world = await MiniWorld.start();
    temp = await Directory.systemTemp.createTemp('downloader_cancel_test');
  });

  tearDown(() async {
    await world.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  DownloadTask taskFor(String url, {int size = 0}) => DownloadTask(
    url: Uri.parse(url),
    targetPath: p.join(temp.path, 'file.bin'),
    sha1: '',
    size: size,
  );

  test('a cancel during a stalled transfer surfaces promptly', () async {
    world.stall = Completer<void>().future;
    final url = world.put('/slow.bin', List.filled(4096, 7));
    final cancel = CancelToken();
    final downloader = FileDownloader(
      mirrors: MirrorChain(order: const [DownloadSource.official]),
      retries: 3,
    );

    final future = downloader.download([taskFor(url)], cancel: cancel).toList();

    await Future<void>.delayed(const Duration(milliseconds: 120));
    final stopwatch = Stopwatch()..start();
    cancel.cancel();

    await expectLater(future, throwsA(isA<CancelledException>()));
    stopwatch.stop();

    // Raced, not polled: this must not wait for the 15s idle timeout, nor for
    // three retry attempts.
    expect(
      stopwatch.elapsed,
      lessThan(const Duration(seconds: 2)),
      reason: 'cancelling must not wait for the client idle timeout',
    );

    // The half-written file must not be left behind either.
    expect(
      Directory(temp.path)
          .listSync()
          .whereType<File>()
          .any((f) => f.path.endsWith('.part')),
      isFalse,
    );
    downloader.close();
  });

  test('a cancel is not retried as a source failure', () async {
    // If the cancel were swallowed into the mirror loop, the server would see
    // more than one request for the same file.
    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests++;
      request.response.add(List.filled(64, 1));
      await request.response.flush();
      // Never closes: the body stays open like a stalled connection.
    });
    addTearDown(() => server.close(force: true));

    final cancel = CancelToken()..cancel();
    final downloader = FileDownloader(
      mirrors: MirrorChain(order: const [DownloadSource.official]),
      retries: 3,
    );

    await expectLater(
      downloader.download([
        taskFor('http://127.0.0.1:${server.port}/stall.bin'),
      ], cancel: cancel).toList(),
      throwsA(isA<CancelledException>()),
    );
    expect(
      requests,
      lessThanOrEqualTo(1),
      reason: 'an empty token must not reach the network at all',
    );
    downloader.close();
  });

  test('an already-cancelled token never starts a transfer', () async {
    final url = world.put('/never.bin', List.filled(16, 1));
    final cancel = CancelToken()..cancel();
    final downloader = FileDownloader(
      mirrors: MirrorChain(order: const [DownloadSource.official]),
    );

    await expectLater(
      downloader.download([taskFor(url)], cancel: cancel).toList(),
      throwsA(isA<CancelledException>()),
    );
    expect(File(p.join(temp.path, 'file.bin')).existsSync(), isFalse);
    downloader.close();
  });

  test(
    'an ordinary download still works with a token that never fires',
    () async {
      final url = world.put('/ok.bin', List.filled(32, 9));
      final cancel = CancelToken();
      final downloader = FileDownloader(
        mirrors: MirrorChain(order: const [DownloadSource.official]),
      );

      await downloader.download([taskFor(url)], cancel: cancel).toList();
      expect(
        File(p.join(temp.path, 'file.bin')).readAsBytesSync(),
        List.filled(32, 9),
      );
      downloader.close();
    },
  );
}
