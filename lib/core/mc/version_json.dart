import 'rules.dart';

/// A downloadable file described by Mojang metadata.
class DownloadArtifact {
  const DownloadArtifact({
    required this.path,
    required this.url,
    required this.sha1,
    required this.size,
  });

  factory DownloadArtifact.fromJson(Map<String, dynamic> json) =>
      DownloadArtifact(
        path: json['path'] as String? ?? '',
        url: json['url'] as String? ?? '',
        sha1: json['sha1'] as String? ?? '',
        size: (json['size'] as num?)?.toInt() ?? 0,
      );

  final String path;
  final String url;
  final String sha1;
  final int size;

  Map<String, dynamic> toJson() => {
    'path': path,
    'url': url,
    'sha1': sha1,
    'size': size,
  };
}

class LibraryDownloads {
  const LibraryDownloads({this.artifact, this.classifiers = const {}});

  factory LibraryDownloads.fromJson(Map<String, dynamic> json) =>
      LibraryDownloads(
        artifact: json['artifact'] == null
            ? null
            : DownloadArtifact.fromJson(
                json['artifact'] as Map<String, dynamic>,
              ),
        classifiers:
            (json['classifiers'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, DownloadArtifact.fromJson(v)),
            ) ??
            const {},
      );

  final DownloadArtifact? artifact;
  final Map<String, DownloadArtifact> classifiers;

  Map<String, dynamic> toJson() => {
    if (artifact != null) 'artifact': artifact!.toJson(),
    if (classifiers.isNotEmpty)
      'classifiers': classifiers.map((k, v) => MapEntry(k, v.toJson())),
  };
}

class LibraryExtract {
  const LibraryExtract({this.exclude = const []});

  factory LibraryExtract.fromJson(Map<String, dynamic> json) => LibraryExtract(
    exclude: (json['exclude'] as List?)?.cast<String>() ?? const [],
  );

  final List<String> exclude;

  Map<String, dynamic> toJson() => {'exclude': exclude};
}

/// One entry of the `libraries` array.
class Library {
  const Library({
    required this.name,
    this.downloads,
    this.natives,
    this.rules,
    this.extract,
  });

  factory Library.fromJson(Map<String, dynamic> json) {
    final downloads = json['downloads'];
    return Library(
      name: json['name'] as String? ?? '',
      downloads: downloads is Map<String, dynamic>
          ? LibraryDownloads.fromJson(downloads)
          : null,
      natives: (json['natives'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, v as String),
      ),
      rules: parseRules(json['rules']),
      extract: json['extract'] == null
          ? null
          : LibraryExtract.fromJson(json['extract'] as Map<String, dynamic>),
    );
  }

  /// Maven-style coordinate: `group:artifact:version[:classifier]`.
  final String name;
  final LibraryDownloads? downloads;

  /// Legacy natives mapping, e.g. `{linux: natives-linux, osx: natives-osx}`.
  final Map<String, String>? natives;
  final List<Rule>? rules;
  final LibraryExtract? extract;

  String get group => name.split(':').first;

  String get artifact {
    final parts = name.split(':');
    return parts.length > 1 ? parts[1] : parts.last;
  }

  String get version => name.split(':').elementAtOrNull(2) ?? '';

  /// Maven classifier (4th segment), e.g. `linux-aarch_64`.
  String get classifier => name.split(':').elementAtOrNull(3) ?? '';

  /// Identity used to decide whether a later entry replaces an earlier one
  /// (Forge and Fabric rely on last-wins to inject patched builds).
  ///
  /// Deliberately excludes the version but **includes the classifier**:
  /// `netty-transport-native-epoll` ships `linux-x86_64` and `linux-aarch_64`
  /// variants that both allow Linux, and collapsing them would put the wrong
  /// native library on an arm64 classpath.
  String get key => '$group:$artifact:$classifier';

  /// `true` when this entry only contributes per-OS natives.
  bool get isNativeOnly => natives != null && downloads?.artifact == null;

  Map<String, dynamic> toJson() => {
    'name': name,
    if (downloads != null) 'downloads': downloads!.toJson(),
    if (natives != null) 'natives': natives,
    if (rules != null) 'rules': rulesToJson(rules),
    if (extract != null) 'extract': extract!.toJson(),
  };
}

/// One entry of `arguments.game` / `arguments.jvm` / `arguments.default-user-jvm`.
///
/// Either a bare string, or `{rules, value}` where value is a string or a list.
class ArgumentEntry {
  const ArgumentEntry({required this.value, this.rules});

  factory ArgumentEntry.fromJson(Object json) {
    if (json is String) return ArgumentEntry(value: [json]);
    if (json is Map<String, dynamic>) {
      final raw = json['value'];
      return ArgumentEntry(
        value: switch (raw) {
          String s => [s],
          List l => l.cast<String>(),
          _ => const [],
        },
        rules: parseRules(json['rules']),
      );
    }
    throw FormatException('unsupported argument entry: $json');
  }

  final List<String> value;
  final List<Rule>? rules;

  Map<String, dynamic> toJson() => {
    if (rules != null) 'rules': rulesToJson(rules),
    'value': value.length == 1 ? value.single : value,
  };
}

class Arguments {
  const Arguments({
    this.game = const [],
    this.jvm = const [],
    this.defaultUserJvm = const [],
  });

  factory Arguments.fromJson(Map<String, dynamic> json) => Arguments(
    game: _parseList(json['game']),
    jvm: _parseList(json['jvm']),
    defaultUserJvm: _parseList(json['default-user-jvm']),
  );

  static List<ArgumentEntry> _parseList(Object? json) {
    if (json is! List) return const [];
    return [for (final e in json) ArgumentEntry.fromJson(e)];
  }

  final List<ArgumentEntry> game;
  final List<ArgumentEntry> jvm;

  /// Present from 1.21.9 / 26.x: a *suggested* memory + GC block for the
  /// launcher to pre-fill. Never passed verbatim — it carries `-Xmx` defaults
  /// the user owns.
  final List<ArgumentEntry> defaultUserJvm;

  Map<String, dynamic> toJson() => {
    if (game.isNotEmpty) 'game': [for (final e in game) e.toJson()],
    if (jvm.isNotEmpty) 'jvm': [for (final e in jvm) e.toJson()],
    if (defaultUserJvm.isNotEmpty)
      'default-user-jvm': [for (final e in defaultUserJvm) e.toJson()],
  };
}

class AssetIndexRef {
  const AssetIndexRef({
    required this.id,
    required this.url,
    required this.sha1,
    required this.size,
    this.totalSize,
  });

  factory AssetIndexRef.fromJson(Map<String, dynamic> json) => AssetIndexRef(
    id: json['id'] as String? ?? '',
    url: json['url'] as String? ?? '',
    sha1: json['sha1'] as String? ?? '',
    size: (json['size'] as num?)?.toInt() ?? 0,
    totalSize: (json['totalSize'] as num?)?.toInt(),
  );

  final String id;
  final String url;
  final String sha1;
  final int size;
  final int? totalSize;

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'sha1': sha1,
    'size': size,
    if (totalSize != null) 'totalSize': totalSize,
  };
}

class JavaVersion {
  const JavaVersion({required this.component, required this.majorVersion});

  factory JavaVersion.fromJson(Map<String, dynamic> json) => JavaVersion(
    component: json['component'] as String? ?? 'jre-legacy',
    majorVersion: (json['majorVersion'] as num?)?.toInt() ?? 8,
  );

  final String component;
  final int majorVersion;

  Map<String, dynamic> toJson() => {
    'component': component,
    'majorVersion': majorVersion,
  };
}

/// A fully parsed version descriptor.
///
/// `raw` keeps the original map so unknown fields (Forge's `_comment_`,
/// `jar`, `inheritsFrom`, `logging`, …) survive a load/save round trip instead
/// of being silently dropped.
class VersionJson {
  const VersionJson({
    required this.id,
    required this.type,
    required this.mainClass,
    required this.libraries,
    required this.arguments,
    required this.raw,
    this.minecraftArguments,
    this.assetIndex,
    this.assets,
    this.downloads = const {},
    this.javaVersion,
    this.inheritsFrom,
    this.jar,
    this.releaseTime,
  });

  factory VersionJson.fromJson(Map<String, dynamic> json) {
    final downloads = (json['downloads'] as Map<String, dynamic>?) ?? const {};
    return VersionJson(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'release',
      mainClass: json['mainClass'] as String? ?? '',
      libraries: [
        for (final l in (json['libraries'] as List? ?? const []))
          if (l is Map<String, dynamic>) Library.fromJson(l),
      ],
      arguments: Arguments.fromJson(
        (json['arguments'] as Map<String, dynamic>?) ?? const {},
      ),
      minecraftArguments: json['minecraftArguments'] as String?,
      assetIndex: json['assetIndex'] == null
          ? null
          : AssetIndexRef.fromJson(json['assetIndex'] as Map<String, dynamic>),
      assets: json['assets'] as String?,
      downloads: downloads.map(
        (k, v) =>
            MapEntry(k, DownloadArtifact.fromJson(v as Map<String, dynamic>)),
      ),
      javaVersion: json['javaVersion'] == null
          ? null
          : JavaVersion.fromJson(json['javaVersion'] as Map<String, dynamic>),
      inheritsFrom: json['inheritsFrom'] as String?,
      jar: json['jar'] as String?,
      releaseTime: json['releaseTime'] as String?,
      raw: json,
    );
  }

  final String id;
  final String type;
  final String mainClass;
  final List<Library> libraries;
  final Arguments arguments;

  /// Pre-1.13 versions express game arguments as one flat string.
  final String? minecraftArguments;
  final AssetIndexRef? assetIndex;
  final String? assets;
  final Map<String, DownloadArtifact> downloads;
  final JavaVersion? javaVersion;
  final String? inheritsFrom;

  /// Set by Forge/Fabric: use another version's client jar.
  final String? jar;
  final String? releaseTime;
  final Map<String, dynamic> raw;

  bool get usesModernArguments =>
      arguments.jvm.isNotEmpty || arguments.game.isNotEmpty;

  /// The `--assetIndex` value the game is actually given.
  String get assetIndexName => assetIndex?.id ?? assets ?? id;

  Map<String, dynamic> toJson() => raw;
}
