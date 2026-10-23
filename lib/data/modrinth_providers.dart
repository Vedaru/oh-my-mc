import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/mods/mod_installer.dart';
import '../core/mods/modrinth.dart';

/// Shared client: Modrinth asks clients to identify themselves and rate-limits
/// anonymous ones, so one connection pool for the whole app is the polite shape.
final modrinthClientProvider = Provider<ModrinthClient>((ref) {
  final client = ModrinthClient();
  ref.onDispose(client.close);
  return client;
});

final modInstallerProvider = Provider<ModInstaller>((ref) {
  final installer = ModInstaller();
  ref.onDispose(installer.close);
  return installer;
});

/// A search, as a value the Ui can key a provider on.
class ModSearchQuery {
  const ModSearchQuery({
    required this.text,
    required this.gameVersion,
    this.loader,
  });

  final String text;
  final String gameVersion;
  final String? loader;

  @override
  bool operator ==(Object other) =>
      other is ModSearchQuery &&
      other.text == text &&
      other.gameVersion == gameVersion &&
      other.loader == loader;

  @override
  int get hashCode => Object.hash(text, gameVersion, loader);

  ModSearchQuery copyWith({String? text}) => ModSearchQuery(
    text: text ?? this.text,
    gameVersion: gameVersion,
    loader: loader,
  );
}

/// Results for one query. Auto-disposed so leaving the dialog drops the page.
final modSearchProvider = FutureProvider.autoDispose
    .family<List<ModrinthProject>, ModSearchQuery>((ref, query) async {
      final client = ref.watch(modrinthClientProvider);
      return client.search(
        query.text,
        gameVersion: query.gameVersion,
        loader: query.loader,
      );
    });

/// One install request: what the search dialog asks for, and what a test can
/// answer without a network.
class ModInstallRequest {
  const ModInstallRequest({
    required this.project,
    required this.gameVersion,
    required this.modsDir,
    this.loader,
  });

  final ModrinthProject project;
  final String gameVersion;
  final String? loader;
  final Directory modsDir;
}

/// The install action, behind a provider so the UI can be tested without
/// downloading jars: the dialog's job is to show progress and failures, not to
/// move bytes.
final modInstallActionProvider =
    Provider<Future<ModInstallOutcome> Function(ModInstallRequest request)>((
      ref,
    ) {
      return (request) => installModrinthProject(
        client: ref.read(modrinthClientProvider),
        installer: ref.read(modInstallerProvider),
        project: request.project,
        gameVersion: request.gameVersion,
        loader: request.loader,
        modsDir: request.modsDir,
      );
    });

/// Installs one project and its required dependencies into a mods directory.
///
/// A function rather than a provider method: it is a one-shot action with a
/// result the caller shows, not state something else watches.
Future<ModInstallOutcome> installModrinthProject({
  required ModrinthClient client,
  required ModInstaller installer,
  required ModrinthProject project,
  required String gameVersion,
  String? loader,
  required Directory modsDir,
  void Function(int done, int total)? onProgress,
}) async {
  final plans = await client.resolve(
    projectId: project.id,
    title: project.title,
    gameVersion: gameVersion,
    loader: loader,
  );
  return installer.install(
    plans: plans,
    modsDir: modsDir.path,
    onProgress: (done, total, _) => onProgress?.call(done, total),
  );
}
