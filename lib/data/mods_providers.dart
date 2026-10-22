import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/instance/instance.dart';
import '../core/mods/mod_scanner.dart';
import 'instance_providers.dart';
import 'launch_factory.dart';

/// The `mods/` directory of the tree an instance actually launches against.
///
/// Shared instances use the global game directory, isolated ones their own - the
/// same rule the launch path uses, so this can never point at a folder the game
/// will not read.
String modsDirFor(LauncherPaths paths, Instance instance) =>
    '${paths.gamePathsFor(instance).root}/mods';

/// Reading and changing the mods folder, behind an interface.
///
/// Two reasons the screen does not call the free functions: the scan is real IO,
/// which a widget test cannot advance inside the fake-async zone, and enabling a
/// mod is a rename whose failure (`both files exist`) must be reported rather than
/// thrown at the UI. Tests replace this with an in-memory fake; the file
/// implementation is covered by test/core/mod_scanner_test.dart.
abstract class ModsRepository {
  Future<List<ModEntry>> scan(String directory);
  Future<String> setEnabled(ModEntry mod, bool enabled);
  Future<void> delete(ModEntry mod);
}

class FileModsRepository implements ModsRepository {
  const FileModsRepository();

  @override
  Future<List<ModEntry>> scan(String directory) => scanMods(directory);

  @override
  Future<String> setEnabled(ModEntry mod, bool enabled) =>
      setModEnabled(mod, enabled);

  @override
  Future<void> delete(ModEntry mod) => deleteMod(mod);
}

final modsRepositoryProvider = Provider<ModsRepository>(
  (ref) => const FileModsRepository(),
);

/// Every mod of one instance, enabled and disabled.
///
/// Auto-disposed and keyed by id: leaving the screen drops the scan, and an
/// instance that changes (a rename, an isolation switch) rebuilds rather than
/// leaving a stale list behind.
final instanceModsProvider = FutureProvider.autoDispose
    .family<List<ModEntry>, String>((ref, instanceId) async {
      final instance = _instanceById(ref, instanceId);
      if (instance == null) return const [];
      // Watched: the folder moves when the instance's isolation changes.
      final paths = ref.watch(launcherPathsProvider);
      return ref.read(modsRepositoryProvider).scan(modsDirFor(paths, instance));
    });

Instance? _instanceById(Ref ref, String id) {
  final state = ref.watch(instanceListProvider);
  if (state is! InstanceListReady) return null;
  for (final instance in state.instances) {
    if (instance.id == id) return instance;
  }
  return null;
}
