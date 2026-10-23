import 'dart:convert';
import 'dart:io';

/// A release as the feed describes it.
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.title,
    required this.notes,
    required this.pageUrl,
    this.installerUrl,
    this.publishedAt,
  });

  /// The tag without its `v`, e.g. `0.2.0`.
  final String version;
  final String title;

  /// Release notes, markdown as written.
  final String notes;
  final String pageUrl;

  /// The `.exe` asset, when the release has one: the whole point of the update is a
  /// file the user can run, not a page they have to read.
  final String? installerUrl;

  final DateTime? publishedAt;
}

/// The outcome of a check.
class UpdateCheck {
  const UpdateCheck({required this.latest, required this.isNewer});

  final ReleaseInfo latest;
  final bool isNewer;
}

/// Compares dotted versions numerically.
///
/// Not string comparison: `0.10.0` is newer than `0.9.0` and sorts before it as text,
/// which is the classic way an updater tells users they are up to date forever.
int compareVersions(String a, String b) {
  List<int> parse(String value) {
    // Strip a leading `v` and anything after `+` (build metadata) or `-` (a
    // pre-release, which this launcher does not ship).
    final cleaned = value
        .trim()
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split('+')
        .first
        .split('-')
        .first;
    return [
      for (final part in cleaned.split('.'))
        int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
    ];
  }

  final left = parse(a);
  final right = parse(b);
  for (var i = 0; i < 3; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l != r) return l.compareTo(r);
  }
  return 0;
}

/// Checks a release feed for a newer build.
///
/// The feed is the project's GitHub releases: that is where the Windows installer is
/// built, so it is the only place whose "latest" is also a file a user can install.
/// A failed check is `null` - the launcher must open and work offline, and an update
/// banner that turns into an error box on a plane is worse than no banner.
class UpdateChecker {
  UpdateChecker({
    HttpClient? client,
    Uri? feed,
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? HttpClient(),
       _feed =
           feed ??
           Uri.parse(
             'https://api.github.com/repos/Vedaru/oh-my-mc/releases/latest',
           );

  final HttpClient _client;
  final Uri _feed;
  final Duration timeout;

  Future<UpdateCheck?> check({required String currentVersion}) async {
    try {
      final request = await _client.getUrl(_feed).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, 'oh-my-mc/launcher');
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      final response = await request.close().timeout(timeout);
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) return null;

      final json = jsonDecode(text);
      if (json is! Map) return null;

      final tag = json['tag_name'] as String? ?? '';
      final latest = _releaseOf(json, tag);
      if (latest == null) return null;
      return UpdateCheck(
        latest: latest,
        isNewer: compareVersions(latest.version, currentVersion) > 0,
      );
    } on Object {
      return null;
    }
  }

  ReleaseInfo? _releaseOf(Map json, String tag) {
    if (tag.isEmpty) return null;
    final assets = json['assets'];
    String? installer;
    if (assets is List) {
      for (final asset in assets) {
        if (asset is! Map) continue;
        final name = asset['name'] as String? ?? '';
        if (!name.endsWith('.exe')) continue;
        installer = asset['browser_download_url'] as String?;
        if (installer != null) break;
      }
    }
    final published = DateTime.tryParse(json['published_at'] as String? ?? '');
    return ReleaseInfo(
      version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
      title: json['name'] as String? ?? tag,
      notes: json['body'] as String? ?? '',
      pageUrl: json['html_url'] as String? ?? '',
      installerUrl: installer,
      publishedAt: published,
    );
  }

  void close() => _client.close(force: true);
}
