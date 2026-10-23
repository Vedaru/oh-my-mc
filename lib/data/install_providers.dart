import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/install/version_installer.dart';
import '../core/install/version_remover.dart';
import '../core/instance/instance.dart';
import '../core/install/install_journal.dart';
import '../core/install/install_log.dart';
import '../core/mc/forge_install.dart';
import '../core/mc/loader_meta.dart';
import '../core/mc/local_host.dart';
import '../core/net/cancellation.dart';
import '../core/net/version_manifest.dart';
import 'instance_providers.dart';
import 'java_providers.dart';
import 'launch_factory.dart';
import 'mirror_preference.dart';

/// The install log the panel renders and the controller writes.
///
/// State is a list of lines so the panel rebuilds on every append; the same lines
/// are appended to `<data>/logs/install.log`, which is what makes an install that
/// was killed mid-flight explainable after a restart.
class InstallLogNotifier extends Notifier<List<String>> {
  late final InstallLog _log;

  @override
  List<String> build() {
    final paths = ref.read(launcherPathsProvider);
    _log = InstallLog(file: File('${paths.data.path}/logs/install.log'));
    return const [];
  }

  void add(String message) {
    _log.add(message);
    // A fresh list each time: `List.unmodifiable` keeps its identity otherwise and
    // the panel would never rebuild.
    state = List.unmodifiable(_log.lines);
  }

  void clear() {
    _log.clear();
    state = const [];
  }
}

final installLogProvider = NotifierProvider<InstallLogNotifier, List<String>>(
  InstallLogNotifier.new,
);

/// Runs one install at a time and exposes its progress.
///
/// One at a time because every install writes to the same `libraries/` and
/// `assets/objects/` trees; two in parallel would race on the same files and one
/// would report the other's half-written jar as a hash mismatch.
sealed class InstallState {
  const InstallState();
}

class InstallIdle extends InstallState {
  const InstallIdle();
}

/// A finished install: the version is on disk, possibly with files that failed
/// verification.
///
/// Keeps only what the screen shows rather than the whole [InstallResult]: the
/// plan holds thousands of tasks and the version tree, and holding that alive
/// for as long as the panel is open buys nothing.
class InstallDone extends InstallState {
  const InstallDone({
    required this.versionId,
    required this.problemCount,
    required this.fileCount,
  });

  final String versionId;

  /// Files that failed verification. Non-zero means "installed, but repair".
  final int problemCount;

  final int fileCount;

  bool get isClean => problemCount == 0;
}

class InstallRunning extends InstallState {
  const InstallRunning({
    required this.versionId,
    required this.progress,
    this.bytesPerSecond,
  });

  final String versionId;
  final InstallProgress progress;

  /// Smoothed by the downloader; `null` until a second sample exists.
  final double? bytesPerSecond;

  /// 0..1 across the whole pipeline. Download is the only phase with a byte
  /// counter, so the other phases contribute a fixed slice each — a bar that
  /// sits at 0% during a one-minute natives unpack looks like a hang.
  double get fraction {
    final download = progress.download;
    if (download != null) return download.fraction;
    final steps = progress.steps;
    if (steps <= 0) return 0;
    return (progress.step - 1) / steps;
  }
}

class InstallFailed extends InstallState {
  const InstallFailed({required this.versionId, required this.message});

  final String versionId;
  final String message;
}

class InstallCancelled extends InstallState {
  const InstallCancelled({required this.versionId});

  final String versionId;
}

/// What the download screen needs to render, whether the user is looking or not.
/// Builds the installer. Overridden in tests with a fake so a widget test never
/// opens a socket, and so an install can be driven to a chosen progress value.
typedef InstallerFactory = VersionInstaller Function();

/// The real factory passes the user's mirror preference; a test override does not
/// need to, which is why the factory type stays argument-free.
final installerFactoryProvider = Provider<InstallerFactory>(
  (ref) =>
      () => VersionInstaller(mirrors: ref.read(mirrorChainProvider)),
);

class InstallController extends Notifier<InstallState> {
  CancelToken? _cancel;
  VersionInstaller? _installer;

  @override
  InstallState build() {
    ref.onDispose(() {
      _cancel?.cancel();
      _installer?.close();
      _installer = null;
    });
    return const InstallIdle();
  }

  bool get isBusy => state is InstallRunning;

  String? _loggedPhase;
  int _loggedPercent = -10;

  /// Publishes progress to the UI and appends to the install log at a human rate.
  ///
  /// Not every event: a 3000-asset install emits thousands per second, and the
  /// interesting lines are always the last few. One line per phase, plus one every
  /// 10% while bytes are moving.
  void _publish(
    CancelToken cancel,
    String versionId,
    InstallProgress progress,
  ) {
    if (cancel.isCancelled || !ref.mounted) return;
    state = InstallRunning(
      versionId: versionId,
      progress: progress,
      bytesPerSecond: progress.download?.bytesPerSecond,
    );

    final phase = progress.phase.name;
    final download = progress.download;
    final percent = download == null || download.bytesTotal == 0
        ? -1
        : download.bytesDone * 100 ~/ download.bytesTotal;
    final phaseChanged = phase != _loggedPhase;
    if (phaseChanged) {
      _loggedPhase = phase;
      // A new phase has a new byte total; the old percentage means nothing.
      _loggedPercent = percent;
    }
    final stepped = percent >= 0 && percent - _loggedPercent >= 10;
    if (!phaseChanged && !stepped) return;
    if (stepped) _loggedPercent = percent;

    ref
        .read(installLogProvider.notifier)
        .add(
          InstallLog.describePhase(
            phase,
            detail: progress.detail,
            step: progress.step == 0 ? null : progress.step,
            steps: progress.steps == 0 ? null : progress.steps,
            bytesDone: download?.bytesDone,
            bytesTotal: download?.bytesTotal,
          ),
        );
  }

  void _log(String message) =>
      ref.read(installLogProvider.notifier).add(message);

  /// Installs [versionId] into the shared game tree.
  ///
  /// Installation deliberately happens against the *shared* tree even when the
  /// caller will launch an isolated instance: libraries and assets are
  /// content-addressed and identical across instances, so copying them per
  /// instance would multiply a 400 MB install by the number of instances.
  Future<void> install(
    String versionId, {
    bool includeAssets = true,
    LoaderKind? loader,
    String? loaderVersion,
  }) async {
    if (isBusy) return;

    final paths = ref.read(launcherPathsProvider);
    final cancel = CancelToken();
    _cancel = cancel;

    final installer = ref.read(installerFactoryProvider)();
    _installer = installer;
    final kind = loader ?? LoaderKind.vanilla;
    // Forge and NeoForge are installed by running their installer jar, not by
    // fetching a profile, so they get their own meta client and a different branch
    // below. Fabric and Quilt publish a complete profile JSON; vanilla has neither.
    final byInstaller = kind == LoaderKind.forge || kind == LoaderKind.neoforge;
    final meta = kind == LoaderKind.fabric || kind == LoaderKind.quilt
        ? LoaderMeta()
        : null;
    final forgeMeta = byInstaller ? ForgeMeta() : null;

    _loggedPhase = null;
    _loggedPercent = -10;
    _log(
      kind == LoaderKind.vanilla
          ? 'install started: $versionId'
          : 'install started: $versionId · ${kind.label}',
    );
    state = InstallRunning(
      versionId: versionId,
      progress: const InstallProgress(phase: InstallPhase.manifest, step: 1),
    );

    try {
      // A loader is not a second pipeline: its meta service hands over a complete
      // version JSON that inherits the game version, so writing that file makes
      // the rest of this install identical to vanilla's.
      var installId = versionId;
      var resolvedLoaderVersion = loaderVersion;
      if (byInstaller) {
        final forge = forgeMeta!;
        var version = resolvedLoaderVersion;
        if (version == null || version.isEmpty) {
          version = await forge.recommendedVersion(
            kind,
            versionId,
            cancel: cancel,
          );
        }
        resolvedLoaderVersion = version;
        _log('${kind.label} build: $version');
        state = InstallRunning(
          versionId: versionId,
          progress: InstallProgress(
            phase: InstallPhase.versionJson,
            step: 2,
            detail: '${kind.label} $version',
          ),
        );

        // Vanilla first: the installer patches `versions/<game>/<game>.jar` in
        // place, and its own libraries are written relative to the same directory.
        final base = await installer.install(
          versionId: versionId,
          paths: paths.gamePaths,
          host: localRuleContext(),
          includeAssets: includeAssets,
          cancel: cancel,
          onProgress: (progress) => _publish(cancel, versionId, progress),
        );

        final runner = ForgeInstaller(meta: forge);
        try {
          installId = await runner.install(
            kind: kind,
            gameVersion: versionId,
            loaderVersion: version,
            paths: paths.gamePaths,
            java: await _installerJava(),
            cancel: cancel,
            onStage: (detail) {
              if (cancel.isCancelled || !ref.mounted) return;
              state = InstallRunning(
                versionId: versionId,
                progress: InstallProgress(
                  phase: InstallPhase.download,
                  step: 3,
                  detail: detail,
                ),
              );
            },
          );
        } finally {
          runner.close();
        }

        // The installer fetched its own libraries; this pass verifies them and
        // fills anything it skipped, without re-touching assets.
        final result = await installer.install(
          versionId: installId,
          paths: paths.gamePaths,
          host: localRuleContext(),
          includeAssets: false,
          cancel: cancel,
          onProgress: (progress) => _publish(cancel, versionId, progress),
        );
        if (!ref.mounted) return;
        state = InstallDone(
          versionId: versionId,
          problemCount: result.verification.problems.length,
          fileCount:
              base.verification.checkedFiles + result.verification.checkedFiles,
        );
        await ref.read(installedVersionsProvider.notifier).refresh();
        await ref
            .read(instanceListProvider.notifier)
            .ensureForVersion(
              installId,
              loader: kind,
              loaderVersion: version,
              name: '$versionId · ${kind.label}',
            );
        return;
      }
      if (meta != null) {
        // `null` means "whatever is current": the download page lets the user pick
        // a loader, not a loader build, which is the choice PCL makes for them too.
        var version = resolvedLoaderVersion;
        if (version == null || version.isEmpty) {
          final available = await meta.loaderVersions(
            kind,
            versionId,
            cancel: cancel,
          );
          if (available.isEmpty) {
            throw StateError('${kind.label} has no build for $versionId');
          }
          version = available.first;
        }
        resolvedLoaderVersion = version;
        _log('${kind.label} build: $version');
        state = InstallRunning(
          versionId: versionId,
          progress: InstallProgress(
            phase: InstallPhase.versionJson,
            step: 2,
            detail: '${kind.label} $version',
          ),
        );
        installId = await LoaderProfileWriter(meta).prepare(
          kind: kind,
          gameVersion: versionId,
          loaderVersion: version,
          paths: paths.gamePaths,
          cancel: cancel,
        );
      }

      final result = await installer.install(
        versionId: installId,
        paths: paths.gamePaths,
        host: localRuleContext(),
        includeAssets: includeAssets,
        cancel: cancel,
        // Also writes the install log: the phase history is the only trace left
        // once the panel is closed or the app restarted.
        onProgress: (progress) => _publish(cancel, versionId, progress),
      );
      if (!ref.mounted) return;
      _log(
        result.verification.problems.isEmpty
            ? 'install done: $installId (${result.verification.checkedFiles} files verified)'
            : 'install finished with ${result.verification.problems.length} '
                  'missing file(s): $installId',
      );
      state = InstallDone(
        versionId: versionId,
        problemCount: result.verification.problems.length,
        fileCount: result.verification.checkedFiles,
      );
      // The list marks rows from the filesystem, so it must be re-read here:
      // otherwise the row the user just installed still offers "Install".
      await ref.read(installedVersionsProvider.notifier).refresh();
      // ...and the launch page needs something to point at: a finished download
      // becomes a launchable instance, exactly as it does in PCL, instead of
      // waiting for the user to invent a name for files they just downloaded.
      await ref
          .read(instanceListProvider.notifier)
          .ensureForVersion(
            installId,
            loader: kind,
            loaderVersion: resolvedLoaderVersion,
            name: kind == LoaderKind.vanilla
                ? null
                : '$versionId · ${kind.label}',
          );
    } on CancelledException {
      _log('install cancelled: $versionId');
      if (ref.mounted) state = InstallCancelled(versionId: versionId);
    } catch (e) {
      // The log is the only place a post-mortem exists once the panel is closed.
      _log('install failed: ${_describe(e)}');
      if (ref.mounted) {
        state = InstallFailed(versionId: versionId, message: _describe(e));
      }
    } finally {
      meta?.close();
      forgeMeta?.close();
      installer.close();
      if (identical(_installer, installer)) _installer = null;
      _cancel = null;
    }
  }

  /// A JVM for the installer jar.
  ///
  /// Forge's processors on 1.20+ are compiled for 17: an 8 will fail halfway
  /// through, and a bare failure is much harder to read than "no Java", so the
  /// newest 17+ runtime is preferred and anything below it is a last resort.
  Future<String> _installerJava() async {
    final runtimes = await ref.read(javaScanProvider.future);
    if (runtimes.isEmpty) {
      throw StateError(
        'Forge needs Java to run its installer: install a runtime from the launch '
        'page, or point at a JDK in Settings > Java',
      );
    }
    final sorted = [...runtimes]
      ..sort((a, b) => b.majorVersion.compareTo(a.majorVersion));
    return sorted
        .firstWhere((r) => r.majorVersion >= 17, orElse: () => sorted.first)
        .path;
  }

  /// Completes an install that was interrupted, or whose files were deleted.
  ///
  /// Deliberately not `install(versionId, loader: …)`: the version JSON is already
  /// on disk (Forge writes its own), and re-running an installer jar to replace 60
  /// missing libraries would take minutes and need a JVM. The shared pipeline
  /// already resolves the inheritance chain, hashes what is present and downloads
  /// only the rest.
  Future<void> repair(String versionId) async {
    if (isBusy) return;
    final paths = ref.read(launcherPathsProvider);
    final cancel = CancelToken();
    _cancel = cancel;
    final installer = ref.read(installerFactoryProvider)();
    _installer = installer;
    _loggedPhase = null;
    _loggedPercent = -10;
    _log('resume started: $versionId');
    state = InstallRunning(
      versionId: versionId,
      progress: const InstallProgress(phase: InstallPhase.manifest, step: 1),
    );
    try {
      final result = await installer.install(
        versionId: versionId,
        paths: paths.gamePaths,
        host: localRuleContext(),
        cancel: cancel,
        onProgress: (progress) => _publish(cancel, versionId, progress),
      );
      if (!ref.mounted) return;
      _log(
        result.verification.problems.isEmpty
            ? 'resume done: $versionId (${result.verification.checkedFiles} files verified)'
            : 'resume finished with ${result.verification.problems.length} '
                  'missing file(s): $versionId',
      );
      state = InstallDone(
        versionId: versionId,
        problemCount: result.verification.problems.length,
        fileCount: result.verification.checkedFiles,
      );
      await ref.read(installedVersionsProvider.notifier).refresh();
      await ref.read(instanceListProvider.notifier).ensureForVersion(versionId);
    } on CancelledException {
      _log('resume cancelled: $versionId');
      if (ref.mounted) state = InstallCancelled(versionId: versionId);
    } catch (e) {
      _log('resume failed: ${_describe(e)}');
      if (ref.mounted) {
        state = InstallFailed(versionId: versionId, message: _describe(e));
      }
    } finally {
      installer.close();
      if (identical(_installer, installer)) _installer = null;
      _cancel = null;
    }
  }

  /// Stops the running install. Returns immediately; the state moves to
  /// [InstallCancelled] when the installer actually unwinds.
  void cancel() => _cancel?.cancel();

  /// Forgets a finished result so the download screen shows a plain row again.
  void reset() {
    if (isBusy) return;
    state = const InstallIdle();
  }

  /// Turns the exception into something a user can act on.
  ///
  /// The installer's own errors are already specific ("no natives resolve for
  /// this platform"), so re-wrapping them in a generic message would be a
  /// regression in information.
  String _describe(Object error) =>
      error is StateError ? error.message : error.toString();
}

/// Versions already present under `versions/`, newest-first by name.
///
/// Derived from the filesystem rather than remembered in a settings file: the
/// user can delete a directory by hand, and a launcher that still offered
/// "Installed" for it would lie.
class InstalledVersions extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    Future.microtask(refresh);
    return const {};
  }

  Future<void> refresh() async {
    final paths = ref.read(launcherPathsProvider);
    final dir = Directory(paths.gamePaths.versions);
    if (!await dir.exists()) {
      // The provider may have been torn down while the listing was in flight; a
      // `state` write after that is a crash in a background task.
      if (ref.mounted) state = const {};
      return;
    }
    final ids = <String>{};
    final incomplete = <String>{};
    await for (final entry in dir.list(followLinks: false)) {
      if (entry is! Directory) continue;
      final id = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      // A version directory without its JSON is a half-deleted install: it
      // cannot be launched, so offering it as installed would be wrong.
      if (!await File(paths.gamePaths.versionJson(id)).exists()) continue;
      // ...and neither is a version whose install was interrupted. The JSON is
      // written first and the libraries last, so its presence says nothing about
      // the 67 jars that may be missing. Keeping it out of `installed` is what
      // leaves the download row clickable, which is the whole recovery path for an
      // install killed mid-flight.
      if (InstallJournal.isIncomplete(paths.gamePaths, id)) {
        incomplete.add(id);
        continue;
      }
      ids.add(id);
    }
    if (ref.mounted) {
      state = ids;
      ref.read(incompleteInstallsProvider.notifier).setAll(incomplete);
    }
  }
}

/// Versions whose install was interrupted: the directory and version JSON exist,
/// the libraries may not.
///
/// Published by [InstalledVersions.refresh] rather than scanning a second time, so
/// the two sets can never disagree.
class IncompleteInstalls extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void setAll(Set<String> ids) => state = ids;
}

final incompleteInstallsProvider =
    NotifierProvider<IncompleteInstalls, Set<String>>(IncompleteInstalls.new);

/// The version list, loaded once per session and cached on disk by the service.
sealed class VersionListState {
  const VersionListState();
}

class VersionListLoading extends VersionListState {
  const VersionListLoading();
}

class VersionListReady extends VersionListState {
  const VersionListReady(this.manifest, {this.fromCache = false});

  final VersionManifest manifest;

  /// True when the network failed and the on-disk manifest was used. The user
  /// should know the list may be out of date.
  final bool fromCache;
}

class VersionListFailed extends VersionListState {
  const VersionListFailed(this.message);

  final String message;
}

/// Builds the manifest service. Overridden in tests so the version list comes
/// from a local server instead of the internet.
typedef ManifestServiceFactory = VersionManifestService Function(
  File cacheFile,
);

final manifestServiceFactoryProvider = Provider<ManifestServiceFactory>(
  (ref) =>
      (cacheFile) => VersionManifestService(cacheFile: cacheFile),
);

class VersionListController extends Notifier<VersionListState> {
  VersionManifestService? _service;

  @override
  VersionListState build() {
    ref.onDispose(() {
      _service?.close();
      _service = null;
    });
    Future.microtask(load);
    return const VersionListLoading();
  }

  Future<void> load({bool forceRefresh = false}) async {
    final paths = ref.read(launcherPathsProvider);
    final service = _service ??= ref.read(manifestServiceFactoryProvider)(
      File('${paths.gamePaths.root}/version_manifest_v2.json'),
    );
    try {
      final manifest = await service.load(forceRefresh: forceRefresh);
      if (!ref.mounted) return;
      state = VersionListReady(manifest, fromCache: service.servedStale);
    } catch (e) {
      if (!ref.mounted) return;
      state = VersionListFailed(e.toString());
    }
  }
}

final installControllerProvider =
    NotifierProvider<InstallController, InstallState>(InstallController.new);

final installedVersionsProvider =
    NotifierProvider<InstalledVersions, Set<String>>(InstalledVersions.new);

final versionListProvider =
    NotifierProvider<VersionListController, VersionListState>(
      VersionListController.new,
    );

/// Where a version is uninstalled from. A provider so a widget test can answer without
/// deleting a directory.
final versionRemoverProvider = Provider<VersionRemover>(
  (ref) => const VersionRemover(),
);
