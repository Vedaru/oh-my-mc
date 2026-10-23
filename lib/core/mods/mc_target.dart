/// What a version id says about the game it runs.
///
/// A version directory name carries the loader and the game version, and the
/// Modrinth search needs both: filtering by the wrong game version returns mods
/// that install cleanly and then fail to load.
library;

import '../instance/instance.dart';

class McTarget {
  const McTarget({required this.gameVersion, this.loader});

  final String gameVersion;

  /// `fabric`, `quilt`, `forge`, `neoforge`, or `null` for vanilla.
  final String? loader;

  bool get isModded => loader != null;

  /// The target an instance runs.
  ///
  /// The instance already knows its loader and game version separately, so the id
  /// is only a fallback: an instance's `versionId` is the *game* version
  /// (`1.20.1`), and reading the loader out of that would call every Fabric
  /// instance vanilla - which is exactly what made the mod search refuse to run.
  static McTarget? fromInstance(Instance instance) {
    if (instance.loader.isModded) {
      return McTarget(
        gameVersion: instance.versionId,
        loader: instance.loader.name,
      );
    }
    return fromVersionId(instance.versionId);
  }

  /// Parses the id shapes the launcher installs:
  ///
  /// - `1.20.1` (vanilla)
  /// - `fabric-loader-0.16.9-1.20.1`, `quilt-loader-0.24.0-1.20.1`
  /// - `1.20.1-forge-47.4.28`
  /// - `neoforge-21.1.264` (NeoForge does not repeat the game version)
  static McTarget? fromVersionId(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return null;

    for (final kind in ['fabric', 'quilt']) {
      final prefix = '$kind-loader-';
      if (trimmed.startsWith(prefix)) {
        final rest = trimmed.substring(prefix.length);
        // `<loader>-<game>`: the game version is the last dash-separated piece,
        // but a snapshot id has no dash, so split from the right.
        final dash = rest.lastIndexOf('-');
        if (dash <= 0) return null;
        return McTarget(gameVersion: rest.substring(dash + 1), loader: kind);
      }
    }

    if (trimmed.startsWith('neoforge-')) {
      // `21.1.264` is MC 1.21.1; `20.4.x` is 1.20.4; `21.0.x` is 1.21.
      final parts = trimmed.substring('neoforge-'.length).split('.');
      if (parts.length < 2) return null;
      final minor = parts[1];
      return McTarget(
        gameVersion: minor == '0' ? '1.${parts[0]}' : '1.${parts[0]}.$minor',
        loader: 'neoforge',
      );
    }

    final forgeAt = trimmed.indexOf('-forge-');
    if (forgeAt > 0) {
      return McTarget(
        gameVersion: trimmed.substring(0, forgeAt),
        loader: 'forge',
      );
    }

    // Anything else is a vanilla id: `1.20.1`, `1.21.2-pre1`, the snapshot
    // `24w14a`, the old `a1.2.6` / `b1.7.3`.
    const vanilla = [
      r'^\d+\.\d+', // 1.20.1, 1.21.2-pre1, 1.21.2-rc1
      r'^\d{2}w\d{2}[a-z]', // 24w14a
      r'^[ab]\d+\.\d+', // a1.2.6, b1.7.3
    ];
    if (vanilla.any((pattern) => RegExp(pattern).hasMatch(trimmed))) {
      return McTarget(gameVersion: trimmed);
    }
    return null;
  }
}
