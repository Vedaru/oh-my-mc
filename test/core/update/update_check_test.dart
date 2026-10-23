import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/update/update_check.dart';

/// A release feed stand-in: the JSON GitHub serves, and the failure modes that matter
/// (rate limit, offline, no installer asset).
class _Feed {
  _Feed._(this._server);

  final HttpServer _server;
  var body = '';
  var status = HttpStatus.ok;

  static Future<_Feed> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _Feed._(server);
    server.listen((request) async {
      request.response.statusCode = fake.status;
      request.response.headers.contentType = ContentType.json;
      request.response.write(fake.body);
      await request.response.close();
    });
    return fake;
  }

  Uri get url => Uri.parse('http://127.0.0.1:${_server.port}/latest');
  Future<void> close() => _server.close(force: true);

  void serve(Map<String, Object?> json) => body = jsonEncode(json);
}

void main() {
  group('version comparison', () {
    test('compares numerically, not as text', () {
      // "0.10.0" < "0.9.0" as strings, which is how an updater tells users they are
      // up to date forever.
      expect(compareVersions('0.10.0', '0.9.0'), greaterThan(0));
      expect(compareVersions('1.0.0', '0.99.99'), greaterThan(0));
      expect(compareVersions('0.1.0', '0.1.0'), 0);
      expect(compareVersions('0.1.0', '0.2.0'), lessThan(0));
    });

    test('ignores the v prefix and build metadata', () {
      expect(compareVersions('v0.2.0', '0.2.0'), 0);
      expect(compareVersions('0.2.0+7', '0.2.0'), 0);
      expect(compareVersions('0.2.0', 'v0.1.9'), greaterThan(0));
    });

    test('a missing component counts as zero', () {
      expect(compareVersions('0.2', '0.2.0'), 0);
      expect(compareVersions('1', '0.9.9'), greaterThan(0));
    });
  });

  group('check', () {
    late _Feed feed;
    late UpdateChecker checker;

    setUp(() async {
      feed = await _Feed.start();
      checker = UpdateChecker(feed: feed.url);
    });

    tearDown(() async {
      checker.close();
      await feed.close();
    });

    test('a newer tag is reported with its installer', () async {
      feed.serve({
        'tag_name': 'v0.2.0',
        'name': '0.2.0',
        'body': '- mods now install with dependencies',
        'html_url': 'https://example.invalid/releases/v0.2.0',
        'published_at': '2026-11-01T10:00:00Z',
        'assets': [
          {
            'name': 'oh-my-mc-0.2.0-windows-x64-setup.exe',
            'browser_download_url': 'https://example.invalid/setup.exe',
          },
          {
            'name': 'notes.txt',
            'browser_download_url': 'https://example.invalid/n.txt',
          },
        ],
      });

      final result = await checker.check(currentVersion: '0.1.0');

      expect(result?.isNewer, isTrue);
      expect(result?.latest.version, '0.2.0');
      expect(result?.latest.notes, contains('dependencies'));
      // The .exe, not the first asset and not the page: an update that lands the user
      // on a web page is not an update.
      expect(result?.latest.installerUrl, 'https://example.invalid/setup.exe');
    });

    test('the same or an older tag is not an update', () async {
      feed.serve({
        'tag_name': 'v0.1.0',
        'name': '0.1.0',
        'body': '',
        'html_url': '',
        'assets': [],
      });

      final result = await checker.check(currentVersion: '0.1.0');

      expect(result?.isNewer, isFalse);
    });

    test('a release without an exe still reports the version', () async {
      feed.serve({
        'tag_name': 'v0.3.0',
        'name': '',
        'body': 'notes',
        'html_url': 'https://x',
        'assets': [],
      });

      final result = await checker.check(currentVersion: '0.1.0');

      expect(result?.latest.version, '0.3.0');
      expect(result?.latest.installerUrl, isNull);
    });

    test('a rate-limited feed is silence, not an error', () async {
      feed.status = HttpStatus.forbidden;
      feed.serve({'message': 'API rate limit exceeded'});

      // Offline, rate-limited and behind a captive portal all land here, and none of
      // them should put an error in front of a user who just wanted to play.
      expect(await checker.check(currentVersion: '0.1.0'), isNull);
    });

    test('garbage is silence too', () async {
      feed.body = 'not json';

      expect(await checker.check(currentVersion: '0.1.0'), isNull);
    });

    test('an unreachable host is silence', () async {
      final offline = UpdateChecker(
        feed: Uri.parse('http://127.0.0.1:1/latest'),
      );

      expect(await offline.check(currentVersion: '0.1.0'), isNull);
      offline.close();
    });
  });
}
