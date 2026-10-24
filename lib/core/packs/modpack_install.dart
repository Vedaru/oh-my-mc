import 'dart:io';

import 'package:path/path.dart' as p;

import '../instance/instance.dart';
import '../mods/modrinth.dart';
import '../net/cancellation.dart';
import 'mrpack.dart';
import 'mrpack_importer.dart';

/// One step of a modpack install, in the order a user sees them.
/// No user-facing strings here: the UI maps a step to a sentence in the user's
/// language, so core stays locale-free.
enum ModpackStep { download, install, create, import }

/// What an install left behind.
class ModpackInstallResult {
  const ModpackInstallResult({
    required this.instance,
    required this.index,
    required this.imported,
    required this.failed,
  });

  /// The instance the pack became. Isolated by construction: a pack's mods must not
  /// leak into every other instance of the same version.
  final Instance instance;

  final MrpackIndex index;

  /// Files the manifest applied.
  final int imported;

  /// Files the manifest could not fetch. A pack that is 95% installed is worth
  /// keeping - the missing file is usually one project that moved - so this is
  /// reported, not thrown.
  final Map<String, String> failed;
}

/// Installs a version and a loader into the shared tree.
///
/// A function rather than an interface: the real implementation is
/// `InstallNotifier.install`, which the download page already drives, and a test can
/// pass a closure that records its arguments.
typedef ModpackVersionInstall = Future<void> Function({
  required String minecraftVersion,
  required LoaderKind loader,
  String? loaderVersion,
});

/// Creates the instance the pack lives in.
typedef ModpackInstanceCreate = Future<Instance> Function({
  required String name,
  required String versionId,
  LoaderKind loader,
  String? loaderVersion,
});

/// Downloads a URL to a file.
typedef ModpackDownload = Future<void> Function(
  Uri url,
  File target, {
  String sha1,
  int size,
  CancelToken? cancel,
});

/// A modpack from Modrinth, installed as a new instance.
///
/// The order is not negotiable: the `.mrpack` has to be read *before* anything is
/// installed, because the manifest - not the download page - is what names the
/// Minecraft version and the loader. A CurseForge-style "install the pack for the
/// version you picked" flow cannot work here: the pack decides.
class ModpackInstaller {
  ModpackInstaller({
    required this.installVersion,
    required this.createInstance,
    required this.download,
    required this.import,
    required this.cacheDir,
    required this.gameDir,
  });

  final ModpackVersionInstall installVersion;
  final ModpackInstanceCreate createInstance;
  final ModpackDownload download;

  /// Unpacks an `.mrpack` into a game directory.
  final Future<MrpackImportResult> Function(
    File pack, {
    required Directory gameDir,
    void Function(int done, int total, String label)? onProgress,
  })
  import;

  /// Where the pack file itself is kept while it is read and applied.
  final Directory cacheDir;

  /// The directory an instance actually launches against.
  final Directory Function(Instance instance) gameDir;

  Future<ModpackInstallResult> install({
    required ModrinthProject project,
    required ModrinthVersion version,
    required String name,
    CancelToken? cancel,
    void Function(ModpackStep step, String detail)? onProgress,
  }) async {
    final file = version.primaryFile;
    if (file == null) {
      throw const FormatException('this pack version has no downloadable file');
    }
    await cacheDir.create(recursive: true);
    final packFile = File(p.join(cacheDir.path, file.filename));

    onProgress?.call(ModpackStep.download, file.filename);
    await download(
      Uri.parse(file.url),
      packFile,
      sha1: file.sha1 ?? '',
      size: file.sizeBytes,
      cancel: cancel,
    );
    cancel?.throwIfCancelled('modpack download');

    final index = await MrpackIndex.read(packFile);
    final loader = loaderKindOf(index.loaderName);

    onProgress?.call(
      ModpackStep.install,
      index.loaderName == null
          ? index.minecraft
          : '${index.minecraft} · ${loader.label}',
    );
    await installVersion(
      minecraftVersion: index.minecraft,
      loader: loader,
      loaderVersion: index.loaderVersion,
    );
    cancel?.throwIfCancelled('modpack install');

    onProgress?.call(ModpackStep.create, name);
    final instance = await createInstance(
      name: name,
      versionId: index.minecraft,
      loader: loader,
      loaderVersion: index.loaderVersion,
    );

    onProgress?.call(ModpackStep.import, index.name);
    final imported = await import(
      packFile,
      gameDir: gameDir(instance),
      onProgress: (done, total, label) =>
          onProgress?.call(ModpackStep.import, '$done/$total $label'),
    );

    // The pack is read and applied; keeping a copy would be a second, stale copy of
    // something the library can re-download.
    if (packFile.existsSync()) await packFile.delete();

    return ModpackInstallResult(
      instance: instance,
      index: index,
      imported: imported.installed.length,
      failed: imported.failed,
    );
  }
}

/// `fabric-loader` -> [LoaderKind.fabric].
///
/// The manifest writes the loader the way Modrinth names it (`fabric-loader`,
/// `quilt-loader`, `forge`, `neoforge`), and every one of them has to map onto the
/// enum the installer understands. An unknown loader is vanilla rather than an
/// exception: the pack still installs, and the missing loader shows up as mods that
/// do nothing, which is a bug report someone can act on.
LoaderKind loaderKindOf(String? manifestName) => switch (manifestName) {
  'fabric-loader' => LoaderKind.fabric,
  'quilt-loader' => LoaderKind.quilt,
  'forge' => LoaderKind.forge,
  'neoforge' => LoaderKind.neoforge,
  _ => LoaderKind.vanilla,
};
