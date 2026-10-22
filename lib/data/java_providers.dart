import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/mc/host.dart';
import '../core/mc/java_catalog.dart';
import '../core/mc/java_manager.dart';
import '../core/mc/java_provisioner.dart';
import '../core/mc/version_json.dart';
import '../core/mc/local_host.dart';
import '../core/net/cancellation.dart';
import 'launch_factory.dart';

/// Builds a provisioner. Overridden in tests so no widget test opens a socket.
typedef JavaProvisionerFactory = JavaProvisioner Function();

final javaProvisionerFactoryProvider = Provider<JavaProvisionerFactory>(
  (ref) => JavaProvisioner.new,
);

/// The catalog of published runtimes, fetched at most once per session.
///
/// Failure is a state, not an exception: the user can still launch with a JVM
/// they already have, so a catalog outage must not take the screen down.
sealed class JavaCatalogState {
  const JavaCatalogState();
}

class JavaCatalogLoading extends JavaCatalogState {
  const JavaCatalogLoading();
}

class JavaCatalogReady extends JavaCatalogState {
  const JavaCatalogReady(this.catalog);

  final JavaCatalog catalog;
}

class JavaCatalogUnavailable extends JavaCatalogState {
  const JavaCatalogUnavailable(this.message);

  final String message;
}

final javaCatalogProvider =
    AsyncNotifierProvider<JavaCatalogController, JavaCatalogState>(
      JavaCatalogController.new,
    );

class JavaCatalogController extends AsyncNotifier<JavaCatalogState> {
  @override
  Future<JavaCatalogState> build() => _fetch(const JavaCatalogLoading());

  Future<JavaCatalogState> _fetch(JavaCatalogState initial) async {
    final provisioner = ref.read(javaProvisionerFactoryProvider)();
    try {
      final catalog = await provisioner.fetchCatalog(Uri.parse(javaCatalogUri));
      return JavaCatalogReady(catalog);
    } catch (e) {
      return JavaCatalogUnavailable(e.toString());
    } finally {
      provisioner.close();
    }
  }

  /// Retries after a failure, which is the only thing a user can do about it.
  Future<void> retry() async {
    state = const AsyncValue.loading();
    state = AsyncValue.data(await _fetch(const JavaCatalogLoading()));
  }
}

/// Which runtime a version needs on this machine, or why there is none.
sealed class JavaRequirement {
  const JavaRequirement();
}

class JavaRequirementSatisfied extends JavaRequirement {
  const JavaRequirementSatisfied(this.runtime);

  final JavaRuntime runtime;
}

/// A downloadable runtime satisfies the version but is not installed yet.
class JavaRequirementDownloadable extends JavaRequirement {
  const JavaRequirementDownloadable({
    required this.choice,
    required this.catalog,
  });

  final JavaRuntimeChoice choice;
  final JavaCatalog catalog;

  int get majorVersion => choice.majorVersion;
}

/// Why no installable runtime exists.
///
/// A code, not a message: `lib/data/` is below the UI and must not hardcode an
/// English sentence the en/zh parity test cannot see. The panel localizes it.
enum JavaUnavailableReason {
  /// Nothing has been installed for this version yet, so there is no version
  /// JSON to read the requirement from.
  versionNotInstalled,

  /// The catalog could not be fetched; the user may still have a local JVM, so
  /// this is a "try again" rather than a dead end.
  catalogUnavailable,

  /// The catalog loaded, but this platform publishes no build that can run the
  /// version (Java 8 on Apple Silicon, for example).
  noBuildForPlatform,
}

/// Nothing installable will satisfy the version.
class JavaRequirementUnavailable extends JavaRequirement {
  const JavaRequirementUnavailable(this.reason, {this.majorVersion});

  final JavaUnavailableReason reason;

  /// The Java major that was wanted, when it is known; `null` when the version
  /// tree itself is missing.
  final int? majorVersion;
}

/// Installs Java runtimes, one at a time.
sealed class JavaInstallState {
  const JavaInstallState();
}

class JavaInstallIdle extends JavaInstallState {
  const JavaInstallIdle();
}

class JavaInstallRunning extends JavaInstallState {
  const JavaInstallRunning({required this.progress, this.bytesPerSecond});

  final JavaProvisionProgress progress;
  final double? bytesPerSecond;

  double get fraction {
    final download = progress.download;
    if (download != null) return download.fraction;
    final steps = progress.steps;
    if (steps <= 0) return 0;
    return (progress.step - 1) / steps;
  }
}

class JavaInstallDone extends JavaInstallState {
  const JavaInstallDone({
    required this.executable,
    required this.majorVersion,
    required this.bytes,
  });

  final String executable;
  final int majorVersion;
  final int bytes;
}

class JavaInstallCancelled extends JavaInstallState {
  const JavaInstallCancelled();
}

class JavaInstallFailed extends JavaInstallState {
  const JavaInstallFailed(this.message);

  final String message;
}

/// Runs one runtime install at a time.
///
/// One at a time for the same reason as version installs: every runtime is
/// extracted into the same tree, and two of them racing would share a staging
/// directory name whenever they target the same component.
class JavaInstallController extends Notifier<JavaInstallState> {
  CancelToken? _cancel;
  JavaProvisioner? _provisioner;

  @override
  JavaInstallState build() {
    ref.onDispose(() {
      _cancel?.cancel();
      _provisioner?.close();
      _provisioner = null;
    });
    return const JavaInstallIdle();
  }

  bool get isBusy => state is JavaInstallRunning;

  /// Downloads and installs [choice], fetching its manifest first.
  ///
  /// The manifest is fetched here rather than passed in: it is one more request
  /// on a separate host, and making the UI await it before the button works
  /// would leave the offer dead for a second with no explanation.
  Future<void> install(JavaRuntimeChoice choice) async {
    if (isBusy) return;

    final paths = ref.read(launcherPathsProvider);
    final cancel = CancelToken();
    _cancel = cancel;

    final provisioner = ref.read(javaProvisionerFactoryProvider)();
    _provisioner = provisioner;
    state = JavaInstallRunning(
      progress: const JavaProvisionProgress(
        phase: JavaProvisionPhase.manifest,
        step: 1,
      ),
    );

    try {
      final manifest = await provisioner.fetchManifest(
        choice.build,
        cancel: cancel,
      );
      final result = await provisioner.provision(
        choice: choice,
        manifest: manifest,
        runtimesDir: javaRuntimesDir(paths.data),
        hostOs: localHostOs,
        cancel: cancel,
        onProgress: (progress) {
          if (cancel.isCancelled || !ref.mounted) return;
          state = JavaInstallRunning(
            progress: progress,
            bytesPerSecond: progress.download?.bytesPerSecond,
          );
        },
      );
      if (!ref.mounted) return;
      state = JavaInstallDone(
        executable: result.executable,
        majorVersion: result.choice.majorVersion,
        bytes: result.bytesWritten,
      );
      // The runtime list is read from the filesystem, so it must be re-scanned
      // or the just-installed runtime does not appear anywhere.
      ref.invalidate(javaRuntimesProvider);
    } on CancelledException {
      if (ref.mounted) state = const JavaInstallCancelled();
    } catch (e) {
      if (ref.mounted) {
        state = JavaInstallFailed(e is StateError ? e.message : e.toString());
      }
    } finally {
      provisioner.close();
      if (identical(_provisioner, provisioner)) _provisioner = null;
      _cancel = null;
    }
  }

  void cancel() => _cancel?.cancel();

  void reset() {
    if (isBusy) return;
    state = const JavaInstallIdle();
  }
}

/// Runtimes the launcher has downloaded, read from disk.
///
/// Deliberately not merged with `JavaManager`'s scan: this list is what the
/// user may delete, and a system JVM must never appear in it.
final javaRuntimesProvider =
    AsyncNotifierProvider<JavaRuntimesController, List<ManagedJavaRuntime>>(
      JavaRuntimesController.new,
    );

class ManagedJavaRuntime {
  const ManagedJavaRuntime({
    required this.executable,
    required this.directory,
    required this.component,
    required this.versionName,
  });

  final String executable;
  final Directory directory;

  /// `java-runtime-gamma`; empty when the directory name is unrecognised.
  final String component;
  final String versionName;

  /// Total bytes on disk, for the settings screen's disk-usage line.
  int get diskBytes => _sizeOf(directory);

  JavaRuntime? get majorVersion {
    final major = javaComponentMajors[component];
    return major == null
        ? null
        : JavaRuntime(
            path: executable,
            majorVersion: major,
            versionString: versionName,
            vendor: 'Mojang',
            arch: HostArch.x86_64,
            source: JavaSource.managed,
          );
  }

  static int _sizeOf(Directory dir) {
    var total = 0;
    if (!dir.existsSync()) return 0;
    for (final entry in dir.listSync(recursive: true, followLinks: false)) {
      if (entry is File) total += entry.lengthSync();
    }
    return total;
  }
}

class JavaRuntimesController extends AsyncNotifier<List<ManagedJavaRuntime>> {
  @override
  Future<List<ManagedJavaRuntime>> build() => _read();

  Future<List<ManagedJavaRuntime>> _read() async {
    final paths = ref.read(launcherPathsProvider);
    final dir = javaRuntimesDir(paths.data);
    if (!await dir.exists()) return const [];

    final runtimes = <ManagedJavaRuntime>[];
    await for (final entry in dir.list(followLinks: false)) {
      if (entry is! Directory) continue;
      if (entry.path.endsWith('.staging')) continue;
      final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      final executable = _executableIn(entry);
      // A directory with no `java` is not a runtime, whatever it is called.
      if (executable == null) continue;
      // `<component>-<version>`: split on the first dash that starts a digit, so
      // `java-runtime-gamma-17.0.15` does not become component `java`.
      final match = RegExp(r'^(.+?)-(\d.*)$').firstMatch(name);
      runtimes.add(
        ManagedJavaRuntime(
          executable: executable.path,
          directory: entry,
          component: match?.group(1) ?? '',
          versionName: match?.group(2) ?? name,
        ),
      );
    }
    runtimes.sort((a, b) => b.versionName.compareTo(a.versionName));
    return runtimes;
  }

  static File? _executableIn(Directory root) {
    for (final relative in const [
      'bin/java',
      'bin/java.exe',
      'jre.bundle/Contents/Home/bin/java',
      'Contents/Home/bin/java',
    ]) {
      final candidate = File('${root.path}/$relative');
      if (candidate.existsSync()) return candidate;
    }
    return null;
  }

  /// Deletes one runtime. Refused while an install is running, because the two
  /// would be writing to the same tree.
  Future<bool> remove(ManagedJavaRuntime runtime) async {
    if (ref.read(javaProvisionControllerProvider) is JavaInstallRunning) {
      return false;
    }
    if (await runtime.directory.exists()) {
      await runtime.directory.delete(recursive: true);
    }
    ref.invalidateSelf();
    return true;
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = AsyncValue.data(await _read());
  }
}

final javaProvisionControllerProvider =
    NotifierProvider<JavaInstallController, JavaInstallState>(
      JavaInstallController.new,
    );

/// Resolves what [requiredMajor] needs on this machine: an installed runtime, a
/// downloadable one, or a refusal.
///
/// Prefers what is already on disk. Downloading 96 MB to replace a working JVM
/// is the kind of thing a launcher should never do silently.
JavaRequirement resolveJavaRequirement({
  required int requiredMajor,
  required List<JavaRuntime> installed,
  required JavaCatalog? catalog,
  required HostOs hostOs,
  required HostArch hostArch,
  String? declaredComponent,
}) {
  final existing = selectRuntime(installed, requiredMajor);
  if (existing != null) return JavaRequirementSatisfied(existing);

  if (catalog == null) {
    return JavaRequirementUnavailable(
      JavaUnavailableReason.catalogUnavailable,
      majorVersion: requiredMajor,
    );
  }

  final platform = javaPlatformKey(hostOs, hostArch);
  try {
    final choice = chooseJavaRuntime(
      catalog: catalog,
      platform: platform,
      requiredMajor: requiredMajor,
      declaredComponent: declaredComponent,
    );
    return JavaRequirementDownloadable(choice: choice, catalog: catalog);
  } on JavaUnavailableException {
    return JavaRequirementUnavailable(
      JavaUnavailableReason.noBuildForPlatform,
      majorVersion: requiredMajor,
    );
  }
}

/// What [versionId] needs on this machine, resolved once per instance.
///
/// Reads the version JSON (which names both the required major and the exact
/// component Mojang tested) rather than guessing from the version id: 1.20 uses
/// Java 17 and 1.21 uses 21, and that mapping is data, not a rule.
final javaRequirementProvider = FutureProvider.family<JavaRequirement, String>((
  ref,
  versionId,
) async {
  final paths = ref.read(launcherPathsProvider);
  final versionFile = File(paths.gamePaths.versionJson(versionId));
  if (!await versionFile.exists()) {
    return const JavaRequirementUnavailable(
      JavaUnavailableReason.versionNotInstalled,
    );
  }
  final version = VersionJson.fromJson(
    jsonDecode(await versionFile.readAsString()) as Map<String, dynamic>,
  );
  final declared = version.javaVersion;

  final installed = <JavaRuntime>[];
  final manager = JavaManager(hostOs: localHostOs);
  installed.addAll(
    await manager.scan(
      environment: const {},
      managedRoots: managedJavaExecutables(paths.data),
    ),
  );

  final catalogState = await ref.watch(javaCatalogProvider.future);
  final catalog = catalogState is JavaCatalogReady
      ? catalogState.catalog
      : null;

  return resolveJavaRequirement(
    requiredMajor: declared?.majorVersion ?? 8,
    declaredComponent: declared?.component,
    installed: installed,
    catalog: catalog,
    hostOs: localHostOs,
    hostArch: localHostArch,
  );
});
