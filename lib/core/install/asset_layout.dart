import 'dart:io';

import 'package:path/path.dart' as p;

import '../mc/asset_index.dart';
import '../mc/install_plan.dart';
import '../net/cancellation.dart';
import 'extract.dart';

/// How many files were materialized, split by layout, for the log and tests.
class AssetMaterialization {
  const AssetMaterialization({
    required this.layout,
    required this.copies,
    required this.failures,
  });

  static const none = AssetMaterialization(
    layout: AssetLayout.hashed,
    copies: 0,
    failures: [],
  );

  final AssetLayout layout;

  /// Number of files written. Zero for [AssetLayout.hashed], where the game
  /// reads objects by hash and no copy is needed.
  final int copies;

  /// Object paths that were referenced by the index but absent on disk. The
  /// caller decides whether that is fatal; `verifyInstall` reports it.
  final List<String> failures;

  bool get neededWork => layout != AssetLayout.hashed;
}

/// Materializes a non-hashed asset index: the step every launcher forgets and
/// every pre-1.7 version then fails on with "missing sound" or a black screen.
///
/// * [AssetLayout.hashed] — nothing to do. Objects stay at
///   `assets/objects/<aa>/<sha1>` and the game resolves them itself.
/// * [AssetLayout.virtual] — objects are *also* copied to
///   `assets/virtual/<indexId>/<name>`, because the game opens them by resource
///   path. One blob can back several names, so this is a copy, not a move.
/// * [AssetLayout.legacyResources] — objects are copied into
///   `<root>/resources/<name>`, which is where pre-1.6 reads them.
///
/// Copies reuse the same file when the name resolves to the same hash, but the
/// destination is always a real file: on Windows, symlinks need developer mode,
/// and a launcher must not depend on that.
Future<AssetMaterialization> materializeAssets({
  required AssetIndex index,
  required GamePaths paths,
  required String indexId,
  CancelToken? cancel,
}) async {
  if (index.layout == AssetLayout.hashed) {
    return AssetMaterialization.none;
  }

  final root = switch (index.layout) {
    AssetLayout.virtual => '${paths.virtualAssets}/$indexId',
    AssetLayout.legacyResources => paths.legacyResources,
    AssetLayout.hashed => paths.virtualAssets,
  };

  final failures = <String>[];
  var copies = 0;

  // Distinct (source, destination, hash) triples. Iterating objects directly
  // would try to copy a shared blob once per name, which for a real 1.6.4 index
  // is 700+ redundant writes of the same file.
  final work = <({String source, String target, String name})>[];
  final seenTargets = <String>{};
  for (final entry in index.objects.entries) {
    final object = entry.value;
    if (object.hash.length < 2) continue;
    // The index is a downloaded file, so its keys are attacker-influenced: a
    // poisoned index is the realistic way to get `../../` into a path join.
    // Reusing the natives guard keeps one definition of "safe entry".
    final name = safeRelativeEntryName(entry.key, 'asset index $indexId');
    final target = p.normalize(p.join(root, name));
    if (!p.isWithin(root, target)) {
      throw FormatException(
        'asset index $indexId tried to write outside the assets dir: '
        '${entry.key}',
      );
    }
    if (!seenTargets.add(target)) continue;
    work.add((
      source: paths.assetObject(object.hash),
      target: target,
      name: name,
    ));
  }

  for (final item in work) {
    cancel?.throwIfCancelled('assets');
    final source = File(item.source);
    if (!source.existsSync()) {
      // The object was not downloaded: report, keep going, let verify decide.
      failures.add(item.name);
      continue;
    }
    final target = File(item.target);
    await target.parent.create(recursive: true);

    // Skip an up-to-date copy: a re-install of the same version should not
    // rewrite 700 files, and a modded instance shares these across versions.
    if (target.existsSync() && target.lengthSync() == source.lengthSync()) {
      copies++;
      continue;
    }
    await source.copy(target.path);
    copies++;
  }

  return AssetMaterialization(
    layout: index.layout,
    copies: copies,
    failures: failures,
  );
}
