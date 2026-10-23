import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/instance/instance.dart';
import '../core/packs/pack_exporter.dart';
import '../core/packs/pack_importer.dart';
import 'instance_providers.dart';
import 'launch_factory.dart';

final packImporterProvider = Provider<PackImporter>((ref) {
  final importer = PackImporter();
  ref.onDispose(importer.close);
  return importer;
});

final packExporterProvider = Provider<PackExporter>((ref) => PackExporter());

/// The result of importing a pack into a brand-new instance.
class PackImportResult {
  const PackImportResult({
    required this.instance,
    required this.pack,
    required this.imported,
  });

  final Instance instance;
  final PackImport pack;

  /// Written paths, for the summary the UI shows.
  final PackImport imported;
}

/// Creates an instance from a pack and unpacks it into that instance's game
/// directory.
///
/// Two steps on purpose: the instance id decides the directory, so it has to exist
/// first - and the pack's own name is what the instance should be called, which is
/// why the header is read before either.
Future<PackImportResult> importPackAsInstance({
  required PackImporter importer,
  required InstanceListNotifier instances,
  required LauncherPaths paths,
  required File file,
  void Function(int done, int total, String label)? onProgress,
}) async {
  final header = await importer.inspect(file);
  final instance = await instances.create(
    name: header.name,
    versionId: header.gameVersion,
    loader: header.loader,
    loaderVersion: header.loaderVersion,
  );

  final gameDir = Directory(paths.gamePathsFor(instance).root);
  final pack = await importer.import(
    file,
    gameDir: gameDir,
    onProgress: onProgress,
  );
  return PackImportResult(instance: instance, pack: pack, imported: pack);
}

/// Writes [instance]'s game directory to [out] as a launcher pack.
Future<int> exportInstancePack({
  required PackExporter exporter,
  required Instance instance,
  required LauncherPaths paths,
  required File out,
}) => exporter.export(
  instance: instance,
  gameDir: Directory(paths.gamePathsFor(instance).root),
  out: out,
);
