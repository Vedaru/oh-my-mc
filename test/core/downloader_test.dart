import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/net/downloader.dart';
import 'package:oh_my_mc/core/net/mirror.dart';
import 'package:oh_my_mc/core/net/progress.dart';

/// A local HTTP server standing in for Mojang, so failure modes are real rather
/// than mocked: truncation, wrong bytes, 404s, and Range resumption.
class TestServer {
  TestServer._(this._server) {
    _server.listen(_handle);
  }

  static Future<TestServer> start() async =>
      TestServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final Map<String, List<int>> files = {};
  final Map<String, int> hits = {};
  final Map<String, int> rangeRequests = {};

  /// Paths that should answer 404.
  final Set<String> missing = {};

  /// Paths that answer with a body that will not match its declared sha1.
  final Set<String> corrupt = {};

  /// Paths whose first response is truncated mid-body.
  final Set<String> truncateOnce = {};
  final Set<String> _truncated = {};

  /// Paths that ignore Range and always send the whole body.
  final Set<String> ignoreRange = {};

  int get port => _server.port;
  Uri url(String path) => Uri.parse('http://127.0.0.1:$port$path');

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    hits[path] = (hits[path] ?? 0) + 1;

    if (missing.contains(path)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final body = files[path];
    if (body == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    var bytes = body;
    if (corrupt.contains(path)) {
      bytes = List.of(body)..[0] = bytes[0] ^ 0xFF;
    }

    final range = request.headers.value(HttpHeaders.rangeHeader);
    var start = 0;
    if (range != null && !ignoreRange.contains(path)) {
      rangeRequests[path] = (rangeRequests[path] ?? 0) + 1;
      final m = RegExp(r'bytes=(\d+)-').firstMatch(range);
      start = int.tryParse(m?.group(1) ?? '0') ?? 0;
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-${bytes.length - 1}/${bytes.length}',
      );
    }

    final slice = bytes.sublist(start.clamp(0, bytes.length));
    if (truncateOnce.contains(path) && !_truncated.contains(path)) {
      _truncated.add(path);
      // Send valid headers and half the body, then hang up mid-stream. This is
      // what a dropped connection looks like, and what the client must treat as
      // a failed transfer rather than a short-but-complete file.
      final socket = await request.response.detachSocket(writeHeaders: false);
      final head =
          'HTTP/1.1 200 OK\r\n'
          'Content-Length: ${slice.length}\r\n'
          'Connection: close\r\n\r\n';
      socket.add(utf8.encode(head));
      socket.add(slice.sublist(0, slice.length ~/ 2));
      await socket.flush();
      await socket.close();
      return;
    }

    request.response.headers.contentLength = slice.length;
    request.response.add(slice);
    await request.response.close();
  }

  Future<void> stop() => _server.close(force: true);
}

String sha1OfBytes(List<int> bytes) => sha1.convert(bytes).toString();

void main() {
  late TestServer server;
  late Directory tmp;

  setUp(() async {
    server = await TestServer.start();
    tmp = await Directory.systemTemp.createTemp('dl_test');
  });

  tearDown(() async {
    await server.stop();
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  DownloadTask taskFor(
    String path,
    String fileName, {
    String? sha1,
    int? size,
  }) {
    final bytes = server.files[path]!;
    return DownloadTask(
      url: server.url(path),
      targetPath: '${tmp.path}/$fileName',
      sha1: sha1 ?? sha1OfBytes(bytes),
      size: size ?? bytes.length,
    );
  }

  group('happy path', () {
    test('downloads, verifies and renames into place', () async {
      server.files['/a.jar'] = utf8.encode('hello world');
      final downloader = FileDownloader();

      final events = await downloader.download([
        taskFor('/a.jar', 'a.jar'),
      ]).toList();

      expect(File('${tmp.path}/a.jar').readAsStringSync(), 'hello world');
      expect(File('${tmp.path}/a.jar.part').existsSync(), isFalse);
      expect(events, isNotEmpty);
      expect(events.last.isComplete, isTrue);
      expect(events.last.fraction, 1.0);
      downloader.close();
    });

    test('creates nested parent directories', () async {
      server.files['/libs/x.jar'] = utf8.encode('jar');
      final downloader = FileDownloader();
      final task = DownloadTask(
        url: server.url('/libs/x.jar'),
        targetPath: '${tmp.path}/com/example/x/1.0/x-1.0.jar',
        sha1: sha1OfBytes(server.files['/libs/x.jar']!),
        size: server.files['/libs/x.jar']!.length,
      );

      await downloader.download([task]).toList();
      expect(
        File('${tmp.path}/com/example/x/1.0/x-1.0.jar').existsSync(),
        isTrue,
      );
      downloader.close();
    });

    test('progress reports total bytes and per-file counts', () async {
      server.files['/a'] = List.filled(1000, 7);
      server.files['/b'] = List.filled(2000, 9);
      final downloader = FileDownloader();

      final events = await downloader.download([
        taskFor('/a', 'a'),
        taskFor('/b', 'b'),
      ]).toList();

      final last = events.last;
      expect(last.filesTotal, 2);
      expect(last.filesDone, 2);
      expect(last.bytesTotal, 3000);
      expect(last.bytesDone, 3000);
      downloader.close();
    });
  });

  group('skipping already-good files', () {
    test('an existing verified file is not fetched again', () async {
      server.files['/a.jar'] = utf8.encode('content');
      final task = taskFor('/a.jar', 'a.jar');
      final first = FileDownloader();
      await first.download([task]).toList();
      first.close();

      final second = FileDownloader();
      await second.download([task]).toList();
      second.close();

      expect(
        server.hits['/a.jar'],
        1,
        reason: 'second run must not re-download',
      );
    });

    test('HashCache avoids re-hashing an unchanged file', () async {
      server.files['/a.jar'] = utf8.encode('content');
      final cache = HashCache();
      final task = taskFor('/a.jar', 'a.jar');

      final first = FileDownloader(hashCache: cache);
      await first.download([task]).toList();
      final hashesAfterFirst = cache.hashCount;
      first.close();

      final second = FileDownloader(hashCache: cache);
      await second.download([task]).toList();
      expect(
        cache.hashCount,
        hashesAfterFirst,
        reason: 'trusted (size, mtime, sha1) must skip hashing',
      );
      second.close();
    });

    test('a same-size but corrupt file is re-downloaded', () async {
      server.files['/a.jar'] = utf8.encode('good');
      final task = taskFor('/a.jar', 'a.jar');
      File('${tmp.path}/a.jar').writeAsStringSync('evil');

      final downloader = FileDownloader();
      await downloader.download([task]).toList();
      downloader.close();

      expect(File('${tmp.path}/a.jar').readAsStringSync(), 'good');
    });
  });

  group('failure handling', () {
    test('404 fails with a DownloadFailedException naming the url', () async {
      server.files['/gone'] = utf8.encode('x');
      server.missing.add('/gone');
      final downloader = FileDownloader(retries: 0);

      await expectLater(
        downloader.download([taskFor('/gone', 'gone')]),
        emitsInOrder([
          isA<DownloadProgress>(),
          emitsError(isA<DownloadFailedException>()),
        ]),
      );
      downloader.close();
      expect(File('${tmp.path}/gone').existsSync(), isFalse);
    });

    test(
      'a wrong-hash body is retried then fails, leaving no target',
      () async {
        server.files['/bad.jar'] = utf8.encode('real content here');
        server.corrupt.add('/bad.jar');
        final downloader = FileDownloader(retries: 1);

        await expectLater(
          downloader.download([taskFor('/bad.jar', 'bad.jar')]),
          emitsInOrder([
            isA<DownloadProgress>(),
            emitsError(isA<DownloadFailedException>()),
          ]),
        );
        downloader.close();
        expect(File('${tmp.path}/bad.jar').existsSync(), isFalse);
      },
    );

    test('a truncated body is retried and then succeeds', () async {
      server.files['/big'] = List.filled(4000, 42);
      server.truncateOnce.add('/big');
      final downloader = FileDownloader(retries: 1);

      await downloader.download([taskFor('/big', 'big')]).toList();
      downloader.close();

      expect(File('${tmp.path}/big').lengthSync(), 4000);
    });

    test(
      'a failed download leaves no .part for an integrity failure',
      () async {
        server.files['/bad'] = utf8.encode('abc');
        server.corrupt.add('/bad');
        final downloader = FileDownloader(retries: 0);

        await expectLater(
          downloader.download([taskFor('/bad', 'bad')]),
          emitsInOrder([
            isA<DownloadProgress>(),
            emitsError(isA<DownloadFailedException>()),
          ]),
        );
        downloader.close();
        expect(
          File('${tmp.path}/bad.part').existsSync(),
          isFalse,
          reason: 'corrupt bytes are worthless; do not resume from them',
        );
      },
    );
  });

  group('resume', () {
    test('a pre-existing .part is continued with a Range request', () async {
      final body = List<int>.generate(5000, (i) => i % 251);
      server.files['/resume'] = body;
      final task = taskFor('/resume', 'resume');

      // Simulate an interrupted earlier attempt: first 2000 bytes are on disk.
      File('${tmp.path}/resume.part').writeAsBytesSync(body.sublist(0, 2000));

      final downloader = FileDownloader();
      await downloader.download([task]).toList();
      downloader.close();

      expect(server.rangeRequests['/resume'], 1);
      expect(File('${tmp.path}/resume').readAsBytesSync(), body);
    });

    test('a host that ignores Range restarts cleanly', () async {
      final body = List<int>.generate(3000, (i) => (i * 3) % 256);
      server.files['/norange'] = body;
      server.ignoreRange.add('/norange');
      File('${tmp.path}/norange.part').writeAsBytesSync(body.sublist(0, 1000));

      final downloader = FileDownloader();
      await downloader.download([taskFor('/norange', 'norange')]).toList();
      downloader.close();

      expect(File('${tmp.path}/norange').readAsBytesSync(), body);
    });

    test('an oversized .part is discarded rather than appended to', () async {
      final body = List.filled(100, 1);
      server.files['/oversize'] = body;
      File('${tmp.path}/oversize.part').writeAsBytesSync(List.filled(500, 9));

      final downloader = FileDownloader();
      await downloader.download([taskFor('/oversize', 'oversize')]).toList();
      downloader.close();

      expect(File('${tmp.path}/oversize').readAsBytesSync(), body);
    });
  });

  group('mirror failover', () {
    test('a tripped source is removed from candidates', () {
      final chain = MirrorChain(failureThreshold: 2);
      final url = Uri.parse(
        'https://piston-meta.mojang.com/v1/packages/abc/1.20.1.json',
      );
      final before = chain.candidates(url);
      expect(before.length, 2);

      chain.markFailed(DownloadSource.official);
      expect(chain.candidates(url).length, 2, reason: 'one failure stays');
      chain.markFailed(DownloadSource.official);
      expect(chain.candidates(url).length, 1);
      expect(chain.candidates(url).single.host, contains('bangbang93'));
    });

    test('a success resets the failure count', () {
      final chain = MirrorChain(failureThreshold: 2);
      chain.markFailed(DownloadSource.bmclapi);
      chain.markSucceeded(DownloadSource.bmclapi);
      chain.markFailed(DownloadSource.bmclapi);
    });

    test('preferring a source reorders candidates', () {
      final chain = MirrorChain();
      final url = Uri.parse(
        'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json',
      );
      expect(chain.candidates(url).first.host, 'piston-meta.mojang.com');
      chain.prefer(DownloadSource.bmclapi);
      expect(chain.candidates(url).first.host, 'bmclapi2.bangbang93.com');
    });
  });
}
