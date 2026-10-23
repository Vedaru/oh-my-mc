import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/game/content.dart';
import '../core/instance/instance.dart';
import '../core/mods/mod_installer.dart';
import '../core/mods/modrinth.dart';
import 'launch_factory.dart';

/// The catalogues the download page offers, and what each installs into.
///
/// `datapack` is the odd one: a datapack belongs to a *world*, not to a version, so
/// its target directory is inside a save and the caller has to choose which one.
enum CatalogKind {
  mod('mod', 'mods'),
  resourcePack('resourcepack', 'resourcepacks'),
  shader('shader', 'shaderpacks'),
  datapack('datapack', 'datapacks');

  const CatalogKind(this.modrinthType, this.folderName);

  /// Modrinth's `project_type` value.
  final String modrinthType;

  /// Directory under the instance's game root - or, for a datapack, under a world.
  final String folderName;

  /// Where an install for [instance] lands, or null when the target depends on a
  /// world the caller has not chosen yet.
  String? targetFor(Instance instance, LauncherPaths paths, {String? world}) {
    final root = paths.gamePathsFor(instance).root;
    if (this == CatalogKind.datapack) {
      return world == null ? null : p.join(root, 'saves', world, folderName);
    }
    return p.join(root, folderName);
  }
}

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

/// A search, as a value the UI can key a provider on.
class ContentSearchQuery {
  const ContentSearchQuery({
    required this.text,
    required this.kind,
    required this.gameVersion,
    this.loader,
  });

  final String text;
  final CatalogKind kind;
  final String gameVersion;
  final String? loader;

  @override
  bool operator ==(Object other) =>
      other is ContentSearchQuery &&
      other.text == text &&
      other.kind == kind &&
      other.gameVersion == gameVersion &&
      other.loader == loader;

  @override
  int get hashCode => Object.hash(text, kind, gameVersion, loader);
}

/// Results for one query. Auto-disposed so leaving the dialog drops the page.
final contentSearchProvider = FutureProvider.autoDispose
    .family<List<ModrinthProject>, ContentSearchQuery>((ref, query) async {
      final client = ref.watch(modrinthClientProvider);
      return client.search(
        query.text,
        projectType: query.kind.modrinthType,
        gameVersion: query.gameVersion,
        loader: query.loader,
      );
    });

/// One install request: what the search dialog asks for, and what a test can
/// answer without a network.
class ContentInstallRequest {
  const ContentInstallRequest({
    required this.project,
    required this.kind,
    required this.gameVersion,
    required this.target,
    this.loader,
    this.enablePack = false,
  });

  final ModrinthProject project;
  final CatalogKind kind;
  final String gameVersion;
  final String? loader;

  /// Absolute directory the files land in.
  final String target;

  /// Turn an installed resource pack on in `options.txt`.
  final bool enablePack;
}

/// The install action, behind a provider so the UI can be tested without
/// downloading jars: the dialog's job is to show progress and failures, not to move
/// bytes.
final contentInstallActionProvider =
    Provider<Future<ModInstallOutcome> Function(ContentInstallRequest request)>(
      (ref) {
        return (request) async {
          final client = ref.read(modrinthClientProvider);
          final plans = await client.resolve(
            projectId: request.project.id,
            title: request.project.title,
            gameVersion: request.gameVersion,
            loader: request.loader,
            projectType: request.kind.modrinthType,
          );
          final outcome = await ref
              .read(modInstallerProvider)
              .install(plans: plans, directory: request.target);

          // A resource pack that lands in the folder but stays off is a download the
          // user has to finish by hand, two menus deep in a screen the game hides.
          if (request.enablePack && outcome.installed.isNotEmpty) {
            final content = GameContent(p.dirname(request.target));
            for (final name in outcome.installed) {
              await content.setResourcePackEnabled(name, true);
            }
          }
          return outcome;
        };
      },
    );
