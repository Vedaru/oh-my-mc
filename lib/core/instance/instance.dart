import 'dart:convert';

/// A launcher-side profile: one version, its settings and where it lives.
///
/// Distinct from `VersionJson`, which is Mojang's description of a *version*.
/// An instance is the user's thing: two instances can share a version and differ
/// in memory, Java and name, which is the entire point of having instances.
///
/// Immutable and value-equal so a Riverpod notifier can compare lists cheaply.
class Instance {
  const Instance({
    required this.id,
    required this.name,
    required this.versionId,
    this.loader = LoaderKind.vanilla,
    this.loaderVersion,
    this.isolation = IsolationKind.shareLibraries,
    this.javaPath,
    this.memoryMb,
    this.jvmArgs = const [],
    this.gameArgs = const [],
    this.windowWidth,
    this.windowHeight,
    this.fullscreen = false,
    this.createdAt,
    this.lastPlayedAt,
    this.totalPlaytime = Duration.zero,
  });

  /// Stable identity, also the directory name under `instances/`.
  ///
  /// A UUID would be tidier, but the directory has to be named something and a
  /// slug is what a user can recognise when they open the folder. Uniqueness is
  /// enforced by the store, which suffixes a counter.
  final String id;

  final String name;

  /// The version this instance runs, e.g. `1.20.1`. For a modloader instance
  /// this is the *game* version and [loaderVersion] is the loader's.
  final String versionId;

  final LoaderKind loader;

  /// e.g. `47.2.0` for NeoForge, `0.15.2` for Fabric. `null` for vanilla.
  final String? loaderVersion;

  /// Whether this instance gets its own `minecraft/` tree or shares the global
  /// one. Sharing is the default because a 1.20.1 install is ~500 MB.
  final IsolationKind isolation;

  /// Per-instance Java override. `null` means "pick by version", which is what
  /// almost everyone wants; the override exists for the user who knows they need
  /// a specific JDK for a mod.
  final String? javaPath;

  /// Per-instance memory ceiling. `null` means "use the global default".
  final int? memoryMb;

  final List<String> jvmArgs;
  final List<String> gameArgs;

  /// Window size handed to the game as `--width/--height`, or `null` for the
  /// game's own default. PCL calls this 窗口大小 and puts it in 版本设置, because a
  /// modpack and a vanilla instance want very different windows.
  final int? windowWidth;
  final int? windowHeight;

  /// `--fullscreen`. Kept separate from the size so a user can resize the window
  /// later without losing the fullscreen preference.
  final bool fullscreen;

  final DateTime? createdAt;
  final DateTime? lastPlayedAt;

  /// Accumulated across sessions, because "which of these did I actually play"
  /// is otherwise unanswerable from the instance list.
  final Duration totalPlaytime;

  /// Directory name, relative to the instances root. Kept separate from [id] only
  /// so the getter survives a later change to how ids are generated.
  String get directoryName => id;

  String get displayName => name.trim().isEmpty ? versionId : name;

  Instance copyWith({
    String? name,
    String? versionId,
    LoaderKind? loader,
    String? loaderVersion,
    bool clearLoaderVersion = false,
    IsolationKind? isolation,
    String? javaPath,
    bool clearJavaPath = false,
    int? memoryMb,
    bool clearMemoryMb = false,
    List<String>? jvmArgs,
    List<String>? gameArgs,
    int? windowWidth,
    int? windowHeight,
    bool? fullscreen,
    bool clearWindowSize = false,
    DateTime? lastPlayedAt,
    Duration? totalPlaytime,
  }) => Instance(
    id: id,
    name: name ?? this.name,
    versionId: versionId ?? this.versionId,
    loader: loader ?? this.loader,
    loaderVersion: clearLoaderVersion
        ? null
        : (loaderVersion ?? this.loaderVersion),
    isolation: isolation ?? this.isolation,
    javaPath: clearJavaPath ? null : (javaPath ?? this.javaPath),
    memoryMb: clearMemoryMb ? null : (memoryMb ?? this.memoryMb),
    jvmArgs: jvmArgs ?? this.jvmArgs,
    gameArgs: gameArgs ?? this.gameArgs,
    // Explicit nulls cannot clear these, so a reset asks for it by name - the
    // same convention as `clearMemoryMb`.
    windowWidth: clearWindowSize ? null : (windowWidth ?? this.windowWidth),
    windowHeight: clearWindowSize ? null : (windowHeight ?? this.windowHeight),
    fullscreen: fullscreen ?? this.fullscreen,
    createdAt: createdAt,
    lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    totalPlaytime: totalPlaytime ?? this.totalPlaytime,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'versionId': versionId,
    'loader': loader.name,
    if (loaderVersion != null) 'loaderVersion': loaderVersion,
    'isolation': isolation.name,
    if (javaPath != null) 'javaPath': javaPath,
    if (memoryMb != null) 'memoryMb': memoryMb,
    if (jvmArgs.isNotEmpty) 'jvmArgs': jvmArgs,
    if (gameArgs.isNotEmpty) 'gameArgs': gameArgs,
    if (windowWidth != null) 'windowWidth': windowWidth,
    if (windowHeight != null) 'windowHeight': windowHeight,
    if (fullscreen) 'fullscreen': true,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (lastPlayedAt != null) 'lastPlayedAt': lastPlayedAt!.toIso8601String(),
    if (totalPlaytime != Duration.zero)
      'totalPlaytimeSeconds': totalPlaytime.inSeconds,
  };

  /// Parses one stored instance.
  ///
  /// Unknown enum names fall back to the default rather than throwing: a file
  /// written by a newer build (or edited by hand) must not make the whole list
  /// unreadable. A missing [id] *is* fatal, because an instance without one
  /// cannot be addressed; the store skips those instead of inventing an identity.
  factory Instance.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('instance has no id');
    }
    return Instance(
      id: id,
      name: json['name'] as String? ?? '',
      versionId: json['versionId'] as String? ?? '',
      loader: LoaderKind.fromName(json['loader'] as String?),
      loaderVersion: json['loaderVersion'] as String?,
      isolation: IsolationKind.fromName(json['isolation'] as String?),
      javaPath: json['javaPath'] as String?,
      memoryMb: (json['memoryMb'] as num?)?.toInt(),
      jvmArgs: _stringList(json['jvmArgs']),
      gameArgs: _stringList(json['gameArgs']),
      windowWidth: _positiveInt(json['windowWidth']),
      windowHeight: _positiveInt(json['windowHeight']),
      fullscreen: json['fullscreen'] == true,
      createdAt: _date(json['createdAt']),
      lastPlayedAt: _date(json['lastPlayedAt']),
      totalPlaytime: Duration(
        seconds: (json['totalPlaytimeSeconds'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  static List<String> _stringList(Object? value) => value is List
      ? value.whereType<String>().toList(growable: false)
      : const [];

  /// A window dimension, or null. Zero and negatives are corrupt values, not
  /// "smallest window": the game refuses them, so they degrade to the default.
  static int? _positiveInt(Object? value) {
    if (value is! num) return null;
    final parsed = value.toInt();
    return parsed > 0 ? parsed : null;
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Instance &&
          other.id == id &&
          other.name == name &&
          other.versionId == versionId &&
          other.loader == loader &&
          other.loaderVersion == loaderVersion &&
          other.isolation == isolation &&
          other.javaPath == javaPath &&
          other.memoryMb == memoryMb &&
          _sameList(other.jvmArgs, jvmArgs) &&
          _sameList(other.gameArgs, gameArgs) &&
          other.windowWidth == windowWidth &&
          other.windowHeight == windowHeight &&
          other.fullscreen == fullscreen &&
          other.lastPlayedAt == lastPlayedAt &&
          other.totalPlaytime == totalPlaytime;

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    versionId,
    loader,
    loaderVersion,
    isolation,
    javaPath,
    memoryMb,
    lastPlayedAt,
    totalPlaytime,
  );

  @override
  String toString() => 'Instance($id, $versionId, ${loader.name})';
}

enum LoaderKind {
  vanilla,
  fabric,
  forge,
  neoforge,
  quilt;

  /// Brand names, and therefore identical in every language.
  String get label => switch (this) {
    LoaderKind.vanilla => 'Vanilla',
    LoaderKind.fabric => 'Fabric',
    LoaderKind.forge => 'Forge',
    LoaderKind.neoforge => 'NeoForge',
    LoaderKind.quilt => 'Quilt',
  };

  static LoaderKind fromName(String? name) => values.firstWhere(
    (v) => v.name == name,
    orElse: () => LoaderKind.vanilla,
  );

  bool get isModded => this != LoaderKind.vanilla;
}

/// How an instance's files are stored.
enum IsolationKind {
  /// One shared `minecraft/` tree; every instance reads the same libraries and
  /// assets. Cheapest by far and the default.
  shareLibraries,

  /// The instance gets its own `minecraft/` inside its directory. Needed when two
  /// instances must see different mods for the same version with no loader
  /// profile to distinguish them.
  isolated;

  static IsolationKind fromName(String? name) => values.firstWhere(
    (v) => v.name == name,
    orElse: () => IsolationKind.shareLibraries,
  );
}

/// Turns a display name into a filesystem-safe directory name.
///
/// Deliberately conservative: only ASCII letters, digits, `-` and `_` survive.
/// An instance directory ends up in a path that a JVM, a shell and occasionally a
/// mod's own `File` handling will all read; allowing spaces and CJK looks nicer
/// until something quotes it wrong. The display name keeps the original, so
/// nothing is lost from the user's point of view.
String slugify(String input) {
  final lower = input.toLowerCase();
  final buffer = StringBuffer();
  var lastWasDash = false;
  for (final rune in lower.runes) {
    final isAlnum =
        (rune >= 0x61 && rune <= 0x7a) || (rune >= 0x30 && rune <= 0x39);
    if (isAlnum) {
      buffer.writeCharCode(rune);
      lastWasDash = false;
    } else if (!lastWasDash && buffer.isNotEmpty) {
      buffer.write('-');
      lastWasDash = true;
    }
  }
  var slug = buffer.toString();
  while (slug.endsWith('-')) {
    slug = slug.substring(0, slug.length - 1);
  }
  return slug.isEmpty ? 'instance' : slug;
}

/// Makes [slug] unique against [taken] by appending `-2`, `-3`, ...
///
/// A numeric suffix rather than a random one because the directory name is
/// user-facing: `1-20-1-2` is diagnosable, `1-20-1-a7f3` is not.
String uniqueSlug(String slug, Iterable<String> taken) {
  final existing = taken.toSet();
  if (!existing.contains(slug)) return slug;
  var n = 2;
  while (existing.contains('$slug-$n')) {
    n++;
  }
  return '$slug-$n';
}

/// Encodes instances for storage. One file, so a partial write cannot interleave
/// two instances.
String encodeInstances(List<Instance> instances) =>
    const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'instances': [for (final i in instances) i.toJson()],
    });

/// Decodes stored instances, skipping entries that cannot be read.
///
/// Skipping rather than throwing is deliberate: one hand-edited broken entry must
/// not cost the user every other instance. The skipped count is returned so the
/// caller can tell the user, instead of silently losing a profile.
({List<Instance> instances, int skipped}) decodeInstances(String source) {
  final Object? root;
  try {
    root = jsonDecode(source);
  } on FormatException {
    return (instances: const <Instance>[], skipped: 1);
  }
  if (root is! Map || root['instances'] is! List) {
    return (instances: const <Instance>[], skipped: 1);
  }

  final result = <Instance>[];
  var skipped = 0;
  final seen = <String>{};
  for (final entry in root['instances'] as List) {
    if (entry is! Map) {
      skipped++;
      continue;
    }
    try {
      final instance = Instance.fromJson(entry.cast<String, Object?>());
      // A duplicate id would make the later instance unaddressable and its
      // directory collide with the first, so the later one is dropped.
      if (!seen.add(instance.id)) {
        skipped++;
        continue;
      }
      result.add(instance);
    } on FormatException {
      skipped++;
    } on TypeError {
      skipped++;
    }
  }
  return (instances: result, skipped: skipped);
}
