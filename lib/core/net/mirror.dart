import 'dart:io';

/// Where a file is being fetched from. Mirrors only cover some kinds, so the
/// caller classifies the URL before asking for a rewrite.
enum EndpointKind {
  /// `piston-meta…/mc/game/version_manifest_v2.json`
  versionManifest,

  /// `piston-meta…/v1/packages/<sha1>/<id>.json`
  versionJson,

  /// `libraries.minecraft.net/<group path>`
  library,

  /// `resources.download.minecraft.net/<aa>/<sha1>`
  asset,

  /// `piston-data…` objects and legacy `launcher*.mojang.com` jars.
  gameFile,
}

/// A download source the user can prefer.
enum DownloadSource {
  official('official'),
  bmclapi('bmclapi');

  const DownloadSource(this.id);

  final String id;
}

/// Maps official Mojang URLs onto a mirror.
///
/// Only deterministic mappings are rewritten. `piston-data` object URLs cannot
/// be rewritten without knowing the version id they belong to, so they always
/// stay on the official host rather than 404 quietly against a mirror.
class MirrorChain {
  MirrorChain({
    List<DownloadSource> order = const [
      DownloadSource.official,
      DownloadSource.bmclapi,
    ],
    this.failureThreshold = 3,
  }) : _order = List.of(order);

  final List<DownloadSource> _order;

  /// Consecutive failures that trip a source out for the rest of the session.
  final int failureThreshold;

  final Map<DownloadSource, int> _consecutiveFailures = {};
  final Set<DownloadSource> _tripped = {};

  List<DownloadSource> get order => List.unmodifiable(_order);

  void prefer(DownloadSource source) {
    if (_order.remove(source)) _order.insert(0, source);
  }

  /// Hosts to try, in order, for [official].
  List<Uri> candidates(Uri official) {
    final kind = classify(official);
    return [
      for (final source in _order)
        if (!_tripped.contains(source)) ?rewrite(official, kind, source),
    ];
  }

  /// Removes [source] from the rotation for the rest of the session.
  void markFailed(DownloadSource source) {
    final n = (_consecutiveFailures[source] ?? 0) + 1;
    _consecutiveFailures[source] = n;
    if (n >= failureThreshold) _tripped.add(source);
  }

  void markSucceeded(DownloadSource source) {
    _consecutiveFailures[source] = 0;
    _tripped.remove(source);
  }

  bool isTripped(DownloadSource source) => _tripped.contains(source);

  void resetHealth() {
    _consecutiveFailures.clear();
    _tripped.clear();
  }

  /// Which source a candidate URL belongs to. Used to attribute failures.
  static DownloadSource sourceOf(Uri uri) => uri.host.contains('bangbang93')
      ? DownloadSource.bmclapi
      : DownloadSource.official;

  static EndpointKind classify(Uri uri) {
    final host = uri.host;
    if (host == 'piston-meta.mojang.com' || host == 'launchermeta.mojang.com') {
      return uri.path.endsWith('version_manifest_v2.json')
          ? EndpointKind.versionManifest
          : EndpointKind.versionJson;
    }
    if (host == 'libraries.minecraft.net') return EndpointKind.library;
    if (host == 'resources.download.minecraft.net') return EndpointKind.asset;
    return EndpointKind.gameFile;
  }

  /// The mirror equivalent of [official] on [source], or `official` itself for
  /// the official source, or `null` when the mirror has no mapping.
  static Uri? rewrite(Uri official, EndpointKind kind, DownloadSource source) {
    if (source == DownloadSource.official) return official;
    const base = 'https://bmclapi2.bangbang93.com';
    final segments = official.pathSegments;

    switch (kind) {
      case EndpointKind.versionManifest:
        return Uri.parse('$base/mc/game/version_manifest_v2.json');

      case EndpointKind.versionJson:
        // …/v1/packages/<sha1>/<id>.json  →  /version/<id>/json
        final file = segments.isEmpty ? '' : segments.last;
        final id = file.endsWith('.json')
            ? file.substring(0, file.length - '.json'.length)
            : file;
        if (id.isEmpty) return null;
        return Uri.parse('$base/version/${Uri.encodeComponent(id)}/json');

      case EndpointKind.library:
        // BMCLAPI's maven path mirrors the group/artifact layout 1:1.
        return official.replace(
          scheme: 'https',
          host: 'bmclapi2.bangbang93.com',
          path: '/maven/${segments.join('/')}',
        );

      case EndpointKind.asset:
        return official.replace(
          scheme: 'https',
          host: 'bmclapi2.bangbang93.com',
          path: '/assets/${segments.join('/')}',
        );

      case EndpointKind.gameFile:
        // No deterministic mapping: keep the official URL.
        return official;
    }
  }
}

/// True when [uri] points at a host we can attribute to a known source.
bool isKnownHost(Uri uri) =>
    uri.host.endsWith('mojang.com') || uri.host.contains('bangbang93');

/// Convenience for tests and diagnostics.
String describeSource(Uri uri) => MirrorChain.sourceOf(uri).id;

/// Guard for absurd responses; a version JSON is ~30-60 KB, assets cap at a few
/// hundred MB. Anything past this is a captive portal or a mirror error page.
const maxMetadataBytes = 8 * 1024 * 1024;

/// Reads a small text body, refusing anything over [maxMetadataBytes].
Future<String> readSmallBody(HttpClientResponse response) async {
  final bytes = <int>[];
  await for (final chunk in response) {
    bytes.addAll(chunk);
    if (bytes.length > maxMetadataBytes) {
      throw HttpException('response exceeded $maxMetadataBytes bytes');
    }
  }
  return String.fromCharCodes(bytes);
}
