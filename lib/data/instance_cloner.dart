import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/instance/instance.dart';
import 'instance_providers.dart';
import 'launch_factory.dart';

/// Copies an instance into a new one.
///
/// Not the same thing as exporting a pack: a clone keeps the *game directory*
/// exactly as it is - worlds, configs, packs - so the two instances can diverge
/// from a common starting point (one for a modpack, one to try a mod on). It shares
/// the installed version files (`versions/`, `libraries/`, `assets/`), which is why
/// this is a directory copy and not a re-download.
class InstanceCloner {
  const InstanceCloner();

  /// Top-level directories a clone does not take with it.
  static const _notCopied = {
    'logs',
    'crash-reports',
    'libraries',
    'assets',
    'versions',
    'natives',
  };

  Future<Instance> clone({
    required Instance source,
    required InstanceListNotifier instances,
    required LauncherPaths paths,
    String? name,
  }) async {
    // The stored instance wins over the one passed in: a caller holding a stale copy
    // (a page that has not rebuilt since the last edit) would otherwise clone the
    // settings as they were, not as they are.
    final current =
        (instances.ready?.instances ?? const <Instance>[])
            .where((i) => i.id == source.id)
            .firstOrNull ??
        source;
    source = current;
    final target = await instances.create(
      name: name ?? '${source.name} (copy)',
      versionId: source.versionId,
      loader: source.loader,
      loaderVersion: source.loaderVersion,
    );
    // `create` copies the settings it knows about; the rest of the per-instance
    // configuration is carried over here so a clone behaves like its source. The
    // *updated* object is the one returned: `create`'s result is the pre-update
    // instance, and handing that back gives a clone whose settings look empty.
    // Always isolated. A shared instance's "game directory" is the launcher-wide
    // one, so cloning it would copy the source onto itself; giving the clone its own
    // directory is what makes "a second copy I can change" true at all.
    final configured = target.copyWith(
      isolation: IsolationKind.isolated,
      memoryMb: source.memoryMb,
      jvmArgs: source.jvmArgs,
      gameArgs: source.gameArgs,
      windowWidth: source.windowWidth,
      windowHeight: source.windowHeight,
      fullscreen: source.fullscreen,
    );
    await instances.update(configured);

    final from = Directory(paths.gamePathsFor(source).root);
    final to = Directory(paths.gamePathsFor(configured).root);
    if (await from.exists()) {
      await _copyTree(from, to);
    }
    return configured;
  }

  /// Copies files, creating directories as needed.
  ///
  /// Skips two kinds of content: `logs/` and `crash-reports/` (they belong to the
  /// session that produced them, and a clone with a crash log has a misleading
  /// history), and `libraries/`, `assets/`, `versions/` - the version files the
  /// installer owns and every instance shares. Copying those would make a clone
  /// gigabytes of files the launcher can re-create on demand.
  Future<void> _copyTree(Directory from, Directory to) async {
    await for (final entity in from.list(recursive: true, followLinks: false)) {
      final relative = p.relative(entity.path, from: from.path);
      final top = p.split(relative).first;
      if (_notCopied.contains(top)) continue;

      final target = p.join(to.path, relative);
      if (entity is Directory) {
        await Directory(target).create(recursive: true);
      } else if (entity is File) {
        await Directory(p.dirname(target)).create(recursive: true);
        await entity.copy(target);
      }
    }
  }
}
