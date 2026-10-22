import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/install/version_installer.dart';
import '../core/mc/local_host.dart';
import '../core/net/cancellation.dart';
import '../core/net/version_manifest.dart';
import 'instance_providers.dart';
import 'launch_factory.dart';

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

final installerFactoryProvider = Provider<InstallerFactory>(
  (ref) => VersionInstaller.new,
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

  /// Installs [versionId] into the shared game tree.
  ///
  /// Installation deliberately happens against the *shared* tree even when the
  /// caller will launch an isolated instance: libraries and assets are
  /// content-addressed and identical across instances, so copying them per
  /// instance would multiply a 400 MB install by the number of instances.
  Future<void> install(String versionId, {bool includeAssets = true}) async {
    if (isBusy) return;

    final paths = ref.read(launcherPathsProvider);
    final cancel = CancelToken();
    _cancel = cancel;

    final installer = ref.read(installerFactoryProvider)();
    _installer = installer;

    state = InstallRunning(
      versionId: versionId,
      progress: const InstallProgress(phase: InstallPhase.manifest, step: 1),
    );

    try {
      final result = await installer.install(
        versionId: versionId,
        paths: paths.gamePaths,
        host: localRuleContext(),
        includeAssets: includeAssets,
        cancel: cancel,
        onProgress: (progress) {
          // A cancelled install keeps emitting for as long as the downloader
          // takes to notice; dropping those keeps the UI from showing progress
          // for work the user already stopped.
          if (cancel.isCancelled || !ref.mounted) return;
          state = InstallRunning(
            versionId: versionId,
            progress: progress,
            bytesPerSecond: progress.download?.bytesPerSecond,
          );
        },
      );
      if (!ref.mounted) return;
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
      await ref.read(instanceListProvider.notifier).ensureForVersion(versionId);
    } on CancelledException {
      if (ref.mounted) state = InstallCancelled(versionId: versionId);
    } catch (e) {
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
    await for (final entry in dir.list(followLinks: false)) {
      if (entry is! Directory) continue;
      final id = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      // A version directory without its JSON is a half-deleted install: it
      // cannot be launched, so offering it as installed would be wrong.
      if (await File(paths.gamePaths.versionJson(id)).exists()) ids.add(id);
    }
    if (ref.mounted) state = ids;
  }
}

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
