/// Asset index handling for both eras.
///
/// The modern/legacy split is **not** derivable from the index id (1.20.1 uses
/// id `5`, 26.3 uses `34`). It comes from flags inside the index file itself:
/// `virtual: true` (1.6–1.7) and `map_to_resources: true` (pre-1.6). Neither
/// flag present means the standard `objects/<first2>/<sha1>` layout.
library;

enum AssetLayout {
  /// Files live at `assets/objects/<aa>/<sha1>` and the game reads them by hash.
  hashed,

  /// Files are also copied to `assets/virtual/<indexId>/<name>` because the
  /// game looks them up by resource path.
  virtual,

  /// Pre-1.6: files are copied straight into `<gameDir>/resources/<name>`.
  legacyResources,
}

class AssetObject {
  const AssetObject({required this.hash, required this.size});

  factory AssetObject.fromJson(Map<String, dynamic> json) => AssetObject(
    hash: json['hash'] as String? ?? '',
    size: (json['size'] as num?)?.toInt() ?? 0,
  );

  final String hash;
  final int size;

  /// Relative location under `assets/objects/`.
  String get objectPath => '${hash.substring(0, 2)}/$hash';

  /// Canonical location of the blob.
  ///
  /// [base] exists because `resources.download.minecraft.net` is not reachable
  /// from a test and is not the only host serving these bytes: a mirror needs a
  /// different base, and injecting it here keeps that decision out of the plan.
  String urlWithBase(String base) => '$base/${hash.substring(0, 2)}/$hash';

  String get url => urlWithBase(defaultAssetBaseUrl);
}

/// Mojang's asset object host.
const defaultAssetBaseUrl = 'https://resources.download.minecraft.net';

class AssetIndex {
  const AssetIndex({
    required this.objects,
    required this.layout,
    required this.totalObjects,
  });

  factory AssetIndex.fromJson(Map<String, dynamic> json) {
    final objects = <String, AssetObject>{
      for (final e in (json['objects'] as Map<String, dynamic>? ?? {}).entries)
        if (e.value is Map<String, dynamic>)
          e.key: AssetObject.fromJson(e.value as Map<String, dynamic>),
    };
    return AssetIndex(
      objects: objects,
      layout: json['virtual'] == true
          ? AssetLayout.virtual
          : json['map_to_resources'] == true
          ? AssetLayout.legacyResources
          : AssetLayout.hashed,
      totalObjects: (json['_sampled_total'] as num?)?.toInt() ?? objects.length,
    );
  }

  final Map<String, AssetObject> objects;
  final AssetLayout layout;

  /// Real object count. Captured indexes are sampled, so this can exceed
  /// `objects.length`; it is what progress percentages should use.
  final int totalObjects;

  /// Distinct hashes: many logical names share one blob.
  Map<String, AssetObject> get distinctBlobs {
    final byHash = <String, AssetObject>{};
    for (final o in objects.values) {
      byHash[o.hash] = o;
    }
    return byHash;
  }
}
