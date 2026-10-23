import 'dart:convert';
import 'dart:io';

import '../net/cancellation.dart';

/// A project in Modrinth's search results.
class ModrinthProject {
  const ModrinthProject({
    required this.id,
    required this.slug,
    required this.title,
    required this.description,
    required this.downloads,
    this.iconUrl,
  });

  factory ModrinthProject.fromJson(Map<String, dynamic> json) =>
      ModrinthProject(
        id: json['project_id'] as String? ?? json['id'] as String? ?? '',
        slug: json['slug'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        downloads: (json['downloads'] as num?)?.toInt() ?? 0,
        iconUrl: json['icon_url'] as String?,
      );

  final String id;
  final String slug;
  final String title;
  final String description;
  final int downloads;
  final String? iconUrl;
}

/// One downloadable file of a version.
class ModrinthFile {
  const ModrinthFile({
    required this.url,
    required this.filename,
    required this.sizeBytes,
    this.primary = false,
    this.sha1,
  });

  factory ModrinthFile.fromJson(Map<String, dynamic> json) => ModrinthFile(
    url: json['url'] as String? ?? '',
    filename: json['filename'] as String? ?? '',
    sizeBytes: (json['size'] as num?)?.toInt() ?? 0,
    primary: json['primary'] == true,
    sha1: (json['hashes'] as Map?)?['sha1'] as String?,
  );

  final String url;
  final String filename;
  final int sizeBytes;
  final bool primary;
  final String? sha1;
}

/// A dependency edge. Only `required` ones are installed: an optional dependency
/// is a suggestion, and pulling those in silently is how a launcher ends up with
/// a mod list the user did not ask for.
class ModrinthDependency {
  const ModrinthDependency({
    required this.projectId,
    required this.type,
    this.versionId,
  });

  factory ModrinthDependency.fromJson(Map<String, dynamic> json) =>
      ModrinthDependency(
        projectId: json['project_id'] as String? ?? '',
        versionId: json['version_id'] as String?,
        type: json['dependency_type'] as String? ?? 'required',
      );

  final String projectId;
  final String? versionId;
  final String type;

  bool get isRequired => type == 'required';
}

/// A published version of a project: the loader/game tags plus the files.
class ModrinthVersion {
  const ModrinthVersion({
    required this.id,
    required this.projectId,
    required this.name,
    required this.versionNumber,
    required this.files,
    required this.dependencies,
    this.loaders = const [],
    this.gameVersions = const [],
  });

  factory ModrinthVersion.fromJson(Map<String, dynamic> json) =>
      ModrinthVersion(
        id: json['id'] as String? ?? '',
        projectId: json['project_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        versionNumber: json['version_number'] as String? ?? '',
        loaders: [
          for (final loader in (json['loaders'] as List? ?? const []))
            if (loader is String) loader,
        ],
        gameVersions: [
          for (final game in (json['game_versions'] as List? ?? const []))
            if (game is String) game,
        ],
        files: [
          for (final file in (json['files'] as List? ?? const []))
            if (file is Map<String, dynamic>) ModrinthFile.fromJson(file),
        ],
        dependencies: [
          for (final dep in (json['dependencies'] as List? ?? const []))
            if (dep is Map<String, dynamic>) ModrinthDependency.fromJson(dep),
        ],
      );

  final String id;
  final String projectId;
  final String name;
  final String versionNumber;

  /// `fabric`, `quilt`, `forge`, `neoforge` - the loader tags the file supports.
  final List<String> loaders;
  final List<String> gameVersions;
  final List<ModrinthFile> files;
  final List<ModrinthDependency> dependencies;

  /// The file to download: Modrinth marks one file `primary`, and a version
  /// without that mark uses its first file.
  ModrinthFile? get primaryFile {
    for (final file in files) {
      if (file.primary) return file;
    }
    return files.isEmpty ? null : files.first;
  }
}

/// One file to download, with the project it belongs to.
class ModInstallPlan {
  const ModInstallPlan({
    required this.projectId,
    required this.title,
    required this.file,
    this.versionId,
    this.reason = 'required',
  });

  final String projectId;
  final String title;
  final ModrinthFile file;
  final String? versionId;

  /// `direct` for the project the user picked, `required` for what it pulls in.
  final String reason;

  String get fileName => file.filename;
}

/// Thrown when a project has no version for the requested game/loader pair.
class ModrinthNoMatch implements Exception {
  const ModrinthNoMatch(this.projectId, this.gameVersion, this.loader);

  final String projectId;
  final String gameVersion;
  final String? loader;

  @override
  String toString() =>
      'no Modrinth version of $projectId for $gameVersion'
      '${loader == null ? '' : ' on $loader'}';
}

/// A small Modrinth v2 client: search, versions, and dependency resolution.
///
/// Only the endpoints the launcher uses, and every lookup takes the game version
/// and loader: "the newest version of Sodium" is meaningless without them - the
/// wrong file installs cleanly and then fails to load in game.
class ModrinthClient {
  ModrinthClient({HttpClient? client, Uri? base})
    : _client = client ?? HttpClient(),
      _base = base ?? Uri.parse('https://api.modrinth.com/v2');

  final HttpClient _client;
  final Uri _base;

  /// Modrinth asks every client to identify itself; an anonymous user agent is
  /// the fastest way to get rate-limited.
  static const _userAgent = 'oh-my-mc/launcher (git.vedaru.cn/Vedaru/oh-my-mc)';

  Future<List<ModrinthProject>> search(
    String query, {
    String projectType = 'mod',
    String? gameVersion,
    String? loader,
    int limit = 20,
    CancelToken? cancel,
  }) async {
    // The type facet keeps shaders out of a resource pack search. The loader facet
    // only applies to mods: a resource pack, a shader or a datapack is not built for
    // Fabric or Forge, and filtering by loader returns nothing for them.
    final facets = <String>[
      '["project_type:$projectType"]',
      if (gameVersion != null) '["versions:$gameVersion"]',
      if (loader != null && projectType == 'mod') '["categories:$loader"]',
    ];
    final uri = _base.replace(
      path: '/v2/search',
      queryParameters: {
        'query': query,
        'limit': '$limit',
        'facets': '[${facets.join(',')}]',
      },
    );
    final body = await _getJson(uri, cancel: cancel);
    final hits = body is Map ? body['hits'] : null;
    if (hits is! List) return const [];
    return [
      for (final hit in hits)
        if (hit is Map<String, dynamic>) ModrinthProject.fromJson(hit),
    ];
  }

  /// The newest version of [projectId] that matches [gameVersion] and [loader].
  Future<ModrinthVersion> versionFor(
    String projectId, {
    required String gameVersion,
    String? loader,
    String projectType = 'mod',
    CancelToken? cancel,
  }) async {
    final uri = _base.replace(
      path: '/v2/project/$projectId/version',
      queryParameters: {
        'game_versions': jsonEncode([gameVersion]),
        // Same rule as search: only mods have a loader tag.
        if (loader != null && projectType == 'mod')
          'loaders': jsonEncode([loader]),
      },
    );
    final body = await _getJson(uri, cancel: cancel);
    if (body is! List) throw StateError('versions of $projectId is not a list');
    for (final entry in body) {
      if (entry is! Map<String, dynamic>) continue;
      final version = ModrinthVersion.fromJson(entry);
      if (version.primaryFile != null) return version;
    }
    throw ModrinthNoMatch(projectId, gameVersion, loader);
  }

  /// Everything [projectId] needs to run, itself included.
  ///
  /// Breadth-first over `required` dependencies with a visited set: mods depend on
  /// libraries that (through aliases) point back at them often enough that a naive
  /// recursion loops, and a duplicate download is harmless while a hang is not.
  /// Optional dependencies are deliberately skipped - pulling those in silently is
  /// how a launcher ends up with a mod list the user did not ask for.
  Future<List<ModInstallPlan>> resolve({
    required String projectId,
    required String title,
    required String gameVersion,
    String? loader,
    String projectType = 'mod',
    CancelToken? cancel,
    void Function(String projectId)? onProject,
  }) async {
    final plans = <ModInstallPlan>[];
    final seen = <String>{};
    final queue = <({String id, String title, String reason})>[
      (id: projectId, title: title, reason: 'direct'),
    ];

    while (queue.isNotEmpty) {
      final item = queue.removeAt(0);
      if (!seen.add(item.id)) continue;
      cancel?.throwIfCancelled('Modrinth');
      onProject?.call(item.id);

      final version = await versionFor(
        item.id,
        gameVersion: gameVersion,
        loader: loader,
        projectType: projectType,
        cancel: cancel,
      );
      final file = version.primaryFile;
      if (file == null) continue;

      plans.add(
        ModInstallPlan(
          projectId: item.id,
          versionId: version.id,
          title: item.title,
          file: file,
          reason: item.reason,
        ),
      );

      for (final dep in version.dependencies) {
        if (!dep.isRequired || dep.projectId.isEmpty) continue;
        queue.add((
          id: dep.projectId,
          title: dep.projectId,
          reason: 'required',
        ));
      }
    }
    return plans;
  }

  Future<Object?> _getJson(Uri uri, {CancelToken? cancel}) async {
    final request = await _client.getUrl(uri);
    request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close();
    cancel?.throwIfCancelled('Modrinth');
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('${uri.path} answered ${response.statusCode}: $text');
    }
    return jsonDecode(text);
  }

  void close() => _client.close(force: true);
}
