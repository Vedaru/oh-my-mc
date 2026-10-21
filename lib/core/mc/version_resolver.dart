import 'version_json.dart';

/// Merges an `inheritsFrom` chain into a single effective version.
///
/// Rules learned from real Forge/Fabric metadata:
/// * libraries from the child are appended, then the list is deduplicated by
///   `group:artifact` keeping the *last* occurrence, because modloaders ship
///   patched builds of libraries the parent also declares;
/// * `mainClass`, `assetIndex`, `javaVersion` and the client download come from
///   the child when it declares them, otherwise the parent's are inherited;
/// * `arguments` concatenate parent-then-child for `game`/`jvm`;
/// * `minecraftArguments` (legacy) is inherited only if the child has none.
///
/// The chain is walked child-first so a grandchild wins over its parent.
VersionJson resolveInheritance(
  VersionJson root,
  VersionJson? Function(String id) lookup,
) {
  if (root.inheritsFrom == null) return root;

  final chain = <VersionJson>[root];
  final seen = <String>{root.id};
  var current = root;
  while (current.inheritsFrom != null) {
    final parentId = current.inheritsFrom!;
    // A cycle in hand-edited metadata must fail loudly, not hang.
    if (!seen.add(parentId)) {
      throw StateError('inheritance cycle at $parentId (${seen.join(' -> ')})');
    }
    final parent = lookup(parentId);
    if (parent == null) {
      throw StateError('missing parent version "$parentId" for ${root.id}');
    }
    chain.add(parent);
    current = parent;
  }

  final base = chain.last;
  final merged = <String, dynamic>{
    ...base.raw,
    'id': root.id,
    'type': root.type,
  };

  // Walk from the top-most parent down so nearer ancestors overwrite.
  for (final v in chain.reversed.skip(1)) {
    _overwritePresent(merged, v.raw, const [
      'mainClass',
      'assets',
      'assetIndex',
      'javaVersion',
      'releaseTime',
      'time',
      'minimumLauncherVersion',
      'logging',
      'complianceLevel',
      'jar',
    ]);
    if (v.minecraftArguments != null) {
      merged['minecraftArguments'] = v.minecraftArguments;
    }
    if (v.downloads.isNotEmpty) {
      merged['downloads'] = {
        ...(merged['downloads'] as Map<String, dynamic>? ?? {}),
        ...v.downloads.map((k, val) => MapEntry(k, val.toJson())),
      };
    }
  }

  final libraries = <Library>[];
  final argsGame = <ArgumentEntry>[];
  final argsJvm = <ArgumentEntry>[];
  final argsUserJvm = <ArgumentEntry>[];

  for (final v in chain.reversed) {
    libraries.addAll(v.libraries);
    argsGame.addAll(v.arguments.game);
    argsJvm.addAll(v.arguments.jvm);
    argsUserJvm.addAll(v.arguments.defaultUserJvm);
  }

  // Not deduped here on purpose: 1.12.2 declares two `lwjgl-platform` entries
  // with complementary rules, so the winner depends on the target platform.
  // `library_graph.dart` filters by rules first, then dedupes.
  merged['libraries'] = [for (final l in libraries) l.toJson()];

  final arguments = <String, dynamic>{
    if (argsGame.isNotEmpty) 'game': [for (final e in argsGame) e.toJson()],
    if (argsJvm.isNotEmpty) 'jvm': [for (final e in argsJvm) e.toJson()],
    if (argsUserJvm.isNotEmpty)
      'default-user-jvm': [for (final e in argsUserJvm) e.toJson()],
  };
  if (arguments.isEmpty) {
    merged.remove('arguments');
  } else {
    merged['arguments'] = arguments;
  }

  return VersionJson.fromJson(merged);
}

void _overwritePresent(
  Map<String, dynamic> target,
  Map<String, dynamic> source,
  List<String> keys,
) {
  for (final k in keys) {
    final v = source[k];
    if (v != null) target[k] = v;
  }
}

/// Last-wins dedupe by `group:artifact`.
///
/// Must be applied *after* rule filtering: 1.12.2 declares two
/// `org.lwjgl.lwjgl:lwjgl-platform` entries with complementary rules, and only
/// one of them is allowed per platform.
List<Library> dedupeLibraries(List<Library> libraries) {
  final byKey = <String, Library>{};
  for (final lib in libraries) {
    byKey[lib.key] = lib;
  }
  return byKey.values.toList();
}
