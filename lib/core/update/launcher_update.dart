import 'dart:convert';
import 'dart:io';

/// A newer release of the launcher itself.
class LauncherUpdate {
  const LauncherUpdate({required this.version, required this.url, this.notes});

  /// The tag with `v` stripped: `v0.2.0` → `0.2.0`.
  final String version;

  /// The release page. The launcher does not install itself - a downloaded installer
  /// is the one update path that works on Windows, Linux and macOS alike, and it keeps
  /// the release as the single source of truth.
  final String url;

  final String? notes;

  /// `0.2.0` → `20200`; enough to order a tag like `0.10.1` above `0.9.9`.
  static int rank(String version) {
    final core = version.split('-').first.split('+').first;
    final parts = core.split('.');
    var value = 0;
    for (var i = 0; i < 3; i++) {
      final part = i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0;
      value =
          value * 100 +
          (part < 0
              ? 0
              : part > 99
              ? 99
              : part);
    }
    return value;
  }

  /// True when [candidate] is newer than [current]. A pre-release suffix is not
  /// compared: a user on `0.2.0` should be told about `0.3.0`, not about `0.3.0-beta`.
  static bool isNewer(String candidate, String current) =>
      rank(candidate) > rank(current);
}

/// Asks GitHub for the latest release.
///
/// Failure is silence: no network, a rate limit, a moved repository - the launcher has
/// nothing to tell the user, and a "could not check for updates" banner on every start
/// is worse than not checking at all.
class LauncherUpdateChecker {
  const LauncherUpdateChecker({
    this.owner = 'Vedaru',
    this.repository = 'oh-my-mc',
    this.timeout = const Duration(seconds: 4),
  });

  final String owner;
  final String repository;
  final Duration timeout;

  Future<LauncherUpdate?> check({required String currentVersion}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(
        Uri.https(
          'api.github.com',
          '/repos/$owner/$repository/releases/latest',
        ),
      );
      request.headers.set('Accept', 'application/vnd.github+json');
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) return null;
      return parse(json, currentVersion: currentVersion);
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// The release JSON → an update, or null when it is not newer. Split out so the shape
  /// of GitHub's answer is testable without a socket.
  static LauncherUpdate? parse(
    Map<String, dynamic> json, {
    required String currentVersion,
  }) {
    final tag = json['tag_name'];
    final url = json['html_url'];
    if (tag is! String || url is! String) return null;
    final version = tag.startsWith('v') ? tag.substring(1) : tag;
    if (!LauncherUpdate.isNewer(version, currentVersion)) return null;
    return LauncherUpdate(
      version: version,
      url: url,
      notes: json['body'] is String ? json['body'] as String : null,
    );
  }
}
