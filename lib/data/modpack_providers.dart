import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/instance/instance.dart';
import '../core/mods/modrinth.dart';
import '../core/packs/mrpack_importer.dart';
import '../core/packs/modpack_install.dart';
import 'instance_providers.dart';
import 'install_providers.dart';
import 'launch_factory.dart';
import 'modrinth_providers.dart';

/// Modrinth modpacks, as the download page searches them.
///
/// No facets: a modpack brings its own Minecraft version and loader, so filtering by the
/// version the user happens to have selected would hide most of the catalogue - and the
/// selected version has nothing to do with what a pack installs.
final modpackSearchProvider = FutureProvider.autoDispose
    .family<List<ModrinthProject>, String>((ref, query) async {
      final client = ref.watch(modrinthClientProvider);
      return client.search(query, projectType: 'modpack', limit: 20);
    });

/// The versions of one modpack, newest first.
final modpackVersionsProvider = FutureProvider.autoDispose
    .family<List<ModrinthVersion>, String>((ref, projectId) {
      return ref.watch(modrinthClientProvider).versions(projectId);
    });

/// The installer, wired to the pieces the download page already has.
///
/// The seams are the existing services rather than new ones: `InstallNotifier` installs a
/// version, `InstanceNotifier` creates the instance, `MrpackImporter` applies the
/// manifest. A modpack is an orchestration of those, not a fifth pipeline.
final modpackInstallerProvider = Provider<ModpackInstaller>((ref) {
  return ModpackInstaller(
    installVersion:
        ({
          required String minecraftVersion,
          required LoaderKind loader,
          String? loaderVersion,
        }) async {
          // `install` is a no-op while another install runs, so a pack started during a
          // download has to be reported rather than silently doing nothing.
          final notifier = ref.read(installControllerProvider.notifier);
          if (notifier.isBusy) {
            throw StateError('another install is already running');
          }
          await notifier.install(
            minecraftVersion,
            loader: loader,
            loaderVersion: loaderVersion,
          );
          final state = ref.read(installControllerProvider);
          if (state is InstallFailed) throw StateError(state.message);
        },
    createInstance:
        ({
          required String name,
          required String versionId,
          LoaderKind loader = LoaderKind.vanilla,
          String? loaderVersion,
        }) => ref
            .read(instanceListProvider.notifier)
            .create(
              name: name,
              versionId: versionId,
              loader: loader,
              loaderVersion: loaderVersion,
            ),
    download: (url, target, {cancel}) async {
      await target.parent.create(recursive: true);
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 30);
      try {
        final request = await client.getUrl(url);
        final response = await request.close();
        if (response.statusCode >= 400) {
          throw HttpException('HTTP ${response.statusCode}', uri: url);
        }
        await response.pipe(target.openWrite());
      } finally {
        client.close(force: true);
      }
    },
    import: (pack, {required gameDir, onProgress}) async {
      final importer = MrpackImporter();
      try {
        return await importer.import(
          pack,
          gameDir: gameDir,
          onProgress: onProgress,
        );
      } finally {
        importer.close();
      }
    },
    cacheDir: Directory(
      p.join(ref.watch(launcherPathsProvider).data.path, 'cache', 'packs'),
    ),
    gameDir: (instance) =>
        Directory(ref.watch(launcherPathsProvider).gamePathsFor(instance).root),
  );
});
