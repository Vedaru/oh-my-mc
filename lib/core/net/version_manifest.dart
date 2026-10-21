import 'dart:convert';
import 'dart:io';

import 'mirror.dart';

/// One row of `version_manifest_v2.json`.
class ManifestVersion {
  const ManifestVersion({
    required this.id,
    required this.type,
    required this.url,
    required this.sha1,
    required this.releaseTime,
  });

  factory ManifestVersion.fromJson(Map<String, dynamic> json) =>
      ManifestVersion(
        id: json['id'] as String? ?? '',
        type: json['type'] as String? ?? 'release',
        url: json['url'] as String? ?? '',
        sha1: json['sha1'] as String? ?? '',
        releaseTime:
            DateTime.tryParse(json['releaseTime'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  final String id;
  final String type;
  final String url;
  final String sha1;
  final DateTime releaseTime;

  bool get isRelease => type == 'release';
  bool get isSnapshot => type == 'snapshot';

  /// `old_beta` / `old_alpha` entries are unplayable without extra work.
  bool get isAncient => type == 'old_beta' || type == 'old_alpha';

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'url': url,
    'sha1': sha1,
    'releaseTime': releaseTime.toIso8601String(),
  };
}

class VersionManifest {
  const VersionManifest({
    required this.latestRelease,
    required this.latestSnapshot,
    required this.versions,
  });

  factory VersionManifest.fromJson(Map<String, dynamic> json) {
    final latest = (json['latest'] as Map<String, dynamic>?) ?? const {};
    return VersionManifest(
      latestRelease: latest['release'] as String? ?? '',
      latestSnapshot: latest['snapshot'] as String? ?? '',
      versions: [
        for (final v in (json['versions'] as List<dynamic>? ?? const []))
          if (v is Map<String, dynamic>) ManifestVersion.fromJson(v),
      ],
    );
  }

  final String latestRelease;
  final String latestSnapshot;
  final List<ManifestVersion> versions;

  ManifestVersion? byId(String id) {
    for (final v in versions) {
      if (v.id == id) return v;
    }
    return null;
  }

  List<ManifestVersion> get releases =>
      versions.where((v) => v.isRelease).toList();

  List<ManifestVersion> get snapshots =>
      versions.where((v) => v.isSnapshot).toList();

  /// Releases grouped by major line (`1.20`, `1.8`, …), newest first, for the
  /// version picker. Modern 26.x ids have no minor line, so they stand alone.
  Map<String, List<ManifestVersion>> get byLine {
    final lines = <String, List<ManifestVersion>>{};
    for (final v in releases) {
      final parts = v.id.split('.');
      final line = parts.length >= 2 ? '${parts[0]}.${parts[1]}' : v.id;
      lines.putIfAbsent(line, () => []).add(v);
    }
    return lines;
  }

  Map<String, dynamic> toJson() => {
    'latest': {'release': latestRelease, 'snapshot': latestSnapshot},
    'versions': [for (final v in versions) v.toJson()],
  };
}

/// Fetches the manifest and caches it on disk for [ttl].
///
/// A stale cache is still better than a failed launch, so a network error falls
/// back to whatever is on disk and only fails when there is nothing at all.
class VersionManifestService {
  VersionManifestService({
    required this.cacheFile,
    this.ttl = const Duration(hours: 6),
    HttpClient? client,
    MirrorChain? mirrors,
    DateTime Function()? clock,
    Uri? manifestUri,
  }) : _client = client ?? HttpClient(),
       mirrors = mirrors ?? MirrorChain(),
       _clock = clock ?? DateTime.now,
       _manifestUri = manifestUri ?? Uri.parse(manifestUrl);

  static const manifestUrl =
      'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json';

  final File cacheFile;
  final Duration ttl;
  final HttpClient _client;
  final MirrorChain mirrors;
  final DateTime Function() _clock;
  final Uri _manifestUri;

  VersionManifest? _memory;

  /// Set when the last fetch came from cache because the network failed.
  bool servedStale = false;

  Future<VersionManifest> load({bool forceRefresh = false}) async {
    if (!forceRefresh && _memory != null) return _memory!;

    final cached = await _readCache();
    if (!forceRefresh &&
        cached != null &&
        _clock().difference(cached.$2) < ttl) {
      servedStale = false;
      return _memory = cached.$1;
    }

    try {
      final fresh = await _fetch();
      await _writeCache(fresh);
      servedStale = false;
      return _memory = fresh;
    } catch (_) {
      if (cached != null) {
        servedStale = true;
        return _memory = cached.$1;
      }
      rethrow;
    }
  }

  Future<VersionManifest> _fetch() async {
    final failures = <Object>[];
    for (final uri in mirrors.candidates(_manifestUri)) {
      try {
        final parsed = VersionManifest.fromJson(await fetchJson(uri, _client));
        if (parsed.versions.isEmpty) {
          throw const FormatException('manifest contained no versions');
        }
        mirrors.markSucceeded(MirrorChain.sourceOf(uri));
        return parsed;
      } catch (e) {
        failures.add(e);
        mirrors.markFailed(MirrorChain.sourceOf(uri));
      }
    }
    throw HttpException('version manifest unavailable: $failures');
  }

  Future<(VersionManifest, DateTime)?> _readCache() async {
    if (!await cacheFile.exists()) return null;
    try {
      final stat = await cacheFile.stat();
      final json =
          jsonDecode(await cacheFile.readAsString()) as Map<String, dynamic>;
      return (VersionManifest.fromJson(json), stat.modified);
    } catch (_) {
      // Corrupt cache: treat as absent rather than crashing the launcher.
      return null;
    }
  }

  Future<void> _writeCache(VersionManifest manifest) async {
    await cacheFile.parent.create(recursive: true);
    final tmp = File('${cacheFile.path}.tmp');
    await tmp.writeAsString(jsonEncode(manifest.toJson()), flush: true);
    await tmp.rename(cacheFile.path);
  }

  void close() => _client.close(force: true);
}

/// GETs [uri] and parses the body as a JSON object, following redirects.
Future<Map<String, dynamic>> fetchJson(Uri uri, HttpClient client) async {
  final request = await client.getUrl(uri);
  request.headers.set(HttpHeaders.acceptHeader, 'application/json');
  final response = await request.close();
  if (response.statusCode >= 400) {
    await response.drain<void>();
    throw HttpException('HTTP ${response.statusCode} from $uri', uri: uri);
  }
  final body = await readSmallBody(response);
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('expected a JSON object from $uri');
  }
  return decoded;
}
