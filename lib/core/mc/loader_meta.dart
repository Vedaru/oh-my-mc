import 'dart:convert';
import 'dart:io';

import '../instance/instance.dart';
import '../net/cancellation.dart';
import 'install_plan.dart';

/// A loader's version list and its installable "profile".
///
/// Fabric and Quilt both publish the *whole* install as one JSON document: a
/// version JSON whose `inheritsFrom` points at the vanilla version and whose
/// libraries are the loader's own. So installing a loader is not a second
/// pipeline — it is writing that JSON into `versions/<id>/` and letting
/// [VersionInstaller] resolve the chain exactly as it does for vanilla.
///
/// Nothing here launches or writes game files; it talks to the meta service and
/// returns parsed JSON, which keeps it unit-testable against a local HTTP server.
class LoaderMeta {
  LoaderMeta({HttpClient? client, Map<LoaderKind, Uri>? hosts})
    : _client = client ?? HttpClient(),
      _hosts = hosts ?? defaultHosts;

  final HttpClient _client;
  final Map<LoaderKind, Uri> _hosts;

  /// Fabric's and Quilt's meta services. Hardcoded like the Mojang manifest: a
  /// mirror for these is a stub, not a configuration knob.
  static final defaultHosts = <LoaderKind, Uri>{
    LoaderKind.fabric: Uri(scheme: 'https', host: 'meta.fabricmc.net'),
    LoaderKind.quilt: Uri(scheme: 'https', host: 'meta.quiltmc.org'),
  };

  /// `fabric-loader-0.16.9-1.20.1`, which is the id the meta service itself
  /// puts in the profile JSON and in the version directory name.
  static String profileId(
    LoaderKind kind,
    String gameVersion,
    String loaderVersion,
  ) => '${kind.name}-loader-$loaderVersion-$gameVersion';

  /// The game version a loader profile id was built for, or `null` when the id is
  /// not one of ours. Used to show "1.20.1 · Fabric 0.16.9" instead of the raw
  /// directory name.
  static String? gameVersionOf(String versionId) {
    for (final kind in [LoaderKind.fabric, LoaderKind.quilt]) {
      final prefix = '${kind.name}-loader-';
      if (!versionId.startsWith(prefix)) continue;
      final rest = versionId.substring(prefix.length);
      final dash = rest.indexOf('-');
      if (dash <= 0 || dash == rest.length - 1) return null;
      return rest.substring(dash + 1);
    }
    return null;
  }

  /// Newest first. Empty when the service has no loader for [gameVersion], which
  /// is normal for a brand-new or very old snapshot.
  Future<List<String>> loaderVersions(
    LoaderKind kind,
    String gameVersion, {
    CancelToken? cancel,
  }) async {
    final base = _hostFor(kind);
    final path = kind == LoaderKind.fabric
        ? '/v2/versions/loader/$gameVersion'
        : '/v3/versions/loader/$gameVersion';
    final body = await _getJson(base.replace(path: path), cancel: cancel);
    if (body is! List) {
      throw StateError('loader list for $gameVersion is not a list');
    }
    return [
      for (final entry in body)
        if (entry is Map && entry['version'] is String)
          entry['version'] as String,
    ];
  }

  /// The installable profile for one (game, loader) pair.
  Future<Map<String, dynamic>> loaderProfile(
    LoaderKind kind,
    String gameVersion,
    String loaderVersion, {
    CancelToken? cancel,
  }) async {
    final base = _hostFor(kind);
    final path = kind == LoaderKind.fabric
        ? '/v2/versions/loader/$gameVersion/$loaderVersion/profile/json'
        : '/v3/versions/loader/$gameVersion/$loaderVersion/profile/json';
    final body = await _getJson(base.replace(path: path), cancel: cancel);
    if (body is! Map<String, dynamic>) {
      throw StateError(
        'loader profile for $gameVersion/$loaderVersion is not an object',
      );
    }
    final id = body['id'];
    if (id is! String || id.isEmpty) {
      throw StateError(
        'loader profile for $gameVersion/$loaderVersion has no id',
      );
    }
    final expected = profileId(kind, gameVersion, loaderVersion);
    if (id != expected) {
      // The directory name is the launch lookup key, so a service-side rename
      // would otherwise write an install nothing can find.
      throw StateError('loader profile id "$id" is not "$expected"');
    }
    if (body['inheritsFrom'] != gameVersion) {
      throw StateError('loader profile for $id does not inherit $gameVersion');
    }
    return body;
  }

  Uri _hostFor(LoaderKind kind) {
    final host = _hosts[kind];
    if (host == null) {
      throw UnsupportedError('${kind.name} has no meta service configured');
    }
    return host;
  }

  Future<Object?> _getJson(Uri url, {CancelToken? cancel}) async {
    final request = await _client.getUrl(url);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close();
    cancel?.throwIfCancelled('loader metadata');
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        '${url.host}${url.path} answered ${response.statusCode}',
      );
    }
    return jsonDecode(text);
  }

  void close() => _client.close(force: true);
}

/// Writes a loader profile into the version tree and returns its version id.
///
/// Separate from installing because the two are separable: this is metadata and a
/// file write (testable with no network), while installing is the shared download
/// pipeline that vanilla already uses. The controller chains them.
class LoaderProfileWriter {
  const LoaderProfileWriter(this.meta);

  final LoaderMeta meta;

  /// Fetches the profile and writes `versions/<id>/<id>.json`, returning the id.
  ///
  /// The write is what makes [VersionInstaller] treat the loader as a first-class
  /// version: it reads a version JSON from disk before it looks in the vanilla
  /// manifest, precisely so a modloader installer can supply one.
  Future<String> prepare({
    required LoaderKind kind,
    required String gameVersion,
    required String loaderVersion,
    required GamePaths paths,
    CancelToken? cancel,
  }) async {
    final profile = await meta.loaderProfile(
      kind,
      gameVersion,
      loaderVersion,
      cancel: cancel,
    );
    final id = profile['id'] as String;
    final file = File(paths.versionJson(id));
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(profile), flush: true);
    return id;
  }
}
