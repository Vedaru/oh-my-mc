import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/instance/instance.dart';
import 'instance_store.dart';
import 'launch_factory.dart';

/// The instance store, overridden at startup like [settingsStoreProvider].
final instanceStoreProvider = Provider<InstanceStore>(
  (ref) =>
      throw StateError('instanceStoreProvider must be overridden at startup'),
);

/// Why a list of instances is not simply a `List<Instance>`.
///
/// Sealed so a screen cannot forget the failure case: `InstanceListLoading`
/// completed without an error is impossible, and `InstanceListFailed` carries the
/// message the user needs.
sealed class InstanceListState {
  const InstanceListState();
}

class InstanceListLoading extends InstanceListState {
  const InstanceListLoading();
}

class InstanceListReady extends InstanceListState {
  const InstanceListReady(this.instances, {this.skipped = 0, this.selectedId});

  final List<Instance> instances;

  /// Entries the store could not parse on load. Non-zero means the user should
  /// be told, once, rather than left wondering where an instance went.
  final int skipped;

  /// The instance the launch screen is acting on. A `null` selection is legal
  /// (a fresh install) and is what makes the play button disabled rather than
  /// guessing.
  final String? selectedId;

  Instance? get selected {
    final id = selectedId;
    if (id == null) return null;
    for (final instance in instances) {
      if (instance.id == id) return instance;
    }
    return null;
  }

  bool get isEmpty => instances.isEmpty;

  @override
  String toString() =>
      'InstanceListReady(${instances.length}, selected: $selectedId)';
}

class InstanceListFailed extends InstanceListState {
  const InstanceListFailed(this.message);

  final String message;
}

/// The live instance list.
///
/// A [Notifier] rather than a `StreamProvider` because every mutation is a whole
/// list write anyway (one JSON file), and because the selection must survive a
/// reload.
class InstanceListNotifier extends Notifier<InstanceListState> {
  @override
  InstanceListState build() {
    // Starting as loading and kicking off the read keeps the first frame cheap;
    // `build` itself must stay synchronous.
    Future.microtask(refresh);
    return const InstanceListLoading();
  }

  InstanceStore get _store => ref.read(instanceStoreProvider);

  /// Bumped by every write. A read that started before the bump is stale and must
  /// not be published.
  ///
  /// Without this, `build`'s own `refresh` and any user edit race: `_commit`
  /// publishes the new list, then awaits the disk write, and during that await an
  /// older `load` completes and republishes the pre-edit list. The edit appears to
  /// silently revert, and a later save persists the reverted value.
  int _generation = 0;

  Future<void> refresh() async {
    final generation = _generation;
    try {
      final instances = await _store.load();
      // A write landed while this read was in flight; the read is older than the
      // truth and would undo it.
      if (generation != _generation) return;
      final previous = state;
      final keep = previous is InstanceListReady ? previous.selectedId : null;
      state = InstanceListReady(
        instances,
        skipped: _store.lastSkipped,
        // Keep the selection only if it still exists; otherwise select the first
        // instance, so the launch screen is never stuck on a deleted profile.
        selectedId: keep != null && instances.any((i) => i.id == keep)
            ? keep
            : (instances.isEmpty ? null : instances.first.id),
      );
    } catch (e) {
      state = InstanceListFailed('$e');
    }
  }

  InstanceListReady? get ready =>
      state is InstanceListReady ? state as InstanceListReady : null;

  /// Writes [instances] and the new selection.
  ///
  /// [selectedId] cannot be cleared by passing `null` — a plain `??` would mean
  /// "keep" and deleting the last instance would leave the launch screen pointing
  /// at an id that no longer exists. [clearSelection] makes that explicit.
  Future<void> _commit(
    List<Instance> instances, {
    String? selectedId,
    bool clearSelection = false,
  }) async {
    final current = ready;
    _generation++;
    state = InstanceListReady(
      instances,
      skipped: current?.skipped ?? 0,
      selectedId: clearSelection ? null : (selectedId ?? current?.selectedId),
    );
    await _store.save(instances);
  }

  /// Adds a new instance, choosing an id that does not collide with an existing
  /// directory. Returns the instance so the caller can navigate to it.
  Future<Instance> create({
    required String name,
    required String versionId,
    LoaderKind loader = LoaderKind.vanilla,
    String? loaderVersion,
  }) async {
    final existing = ready?.instances ?? const <Instance>[];
    final id = uniqueSlug(
      slugify(name.trim().isEmpty ? versionId : name),
      existing.map((i) => i.id),
    );
    final instance = Instance(
      id: id,
      name: name.trim(),
      versionId: versionId,
      loader: loader,
      loaderVersion: loaderVersion,
      createdAt: DateTime.now(),
    );
    await _commit([...existing, instance], selectedId: id);
    return instance;
  }

  /// Makes [versionId] launchable: reuse an instance that already points at it,
  /// otherwise create one named after the version, and select it either way.
  ///
  /// This is PCL's post-download behaviour - a finished download *is* a launchable
  /// card on the launch page - and it is why "I installed 26.3 but cannot play it"
  /// was a real dead end: installing wrote files, and nothing pointed the launcher
  /// at them.
  Future<Instance> ensureForVersion(
    String versionId, {
    LoaderKind loader = LoaderKind.vanilla,
    String? loaderVersion,
    String? name,
  }) async {
    final existing = ready?.instances ?? const <Instance>[];
    for (final instance in existing) {
      if (instance.versionId == versionId && instance.loader == loader) {
        await select(instance.id);
        return instance;
      }
    }
    return create(
      name: name ?? versionId,
      versionId: versionId,
      loader: loader,
      loaderVersion: loaderVersion,
    );
  }

  /// Renames in place. The id does **not** change: it is the directory name, and
  /// moving a multi-hundred-megabyte directory to rename it would be a rude
  /// surprise.
  Future<void> rename(String id, String name) async {
    final existing = ready?.instances ?? const <Instance>[];
    await _commit([
      for (final i in existing)
        if (i.id == id) i.copyWith(name: name.trim()) else i,
    ]);
  }

  /// Removes an instance, and optionally the files it owns.
  ///
  /// Ordering matters: the list is written first, so a failed or partially
  /// failed directory delete leaves stray bytes on disk but never an instance the
  /// store still lists pointing at a folder that is gone. A user can delete the
  /// directory by hand; they cannot recover a deleted profile.
  ///
  /// The delete is refused when [deleteFiles] would reach outside
  /// `<data>/instances/`: [id] is the directory name, and although it is slugified
  /// at creation, a hand-edited `instances.json` can contain `..`. The instance is
  /// still removed from the list, because refusing that would strand it.
  ///
  /// Returns whether the folder is gone. `false` means the list entry was removed
  /// but files remain, which the caller should tell the user about.
  Future<bool> remove(String id, {bool deleteFiles = false}) async {
    final existing = ready?.instances ?? const <Instance>[];
    final remaining = [
      for (final i in existing)
        if (i.id != id) i,
    ];
    await _commit(
      remaining,
      // Deleting the selected instance must move the selection, not leave it
      // pointing at something that is gone.
      selectedId: remaining.isEmpty ? null : remaining.first.id,
      clearSelection: remaining.isEmpty,
    );
    if (!deleteFiles) return true;
    return deleteInstanceFiles(id);
  }

  /// Deletes one instance's directory, never anything above it.
  ///
  /// Returns `true` when there was nothing left to delete, so a caller can tell
  /// "removed" from "removed, but the folder survives" and say so.
  Future<bool> deleteInstanceFiles(String id) async {
    final paths = ref.read(launcherPathsProvider);
    final root = p.canonicalize(paths.instanceRoot.path);
    final target = p.canonicalize(paths.instanceDir(id).path);
    if (!p.isWithin(root, target)) return false;

    final directory = Directory(target);
    if (!await directory.exists()) return true;
    try {
      await directory.delete(recursive: true);
      return true;
    } on FileSystemException {
      // A file held open by a running game is the realistic case on Windows.
      // Surfacing this as an exception would abort a delete the user already
      // confirmed; the list entry is gone either way.
      return false;
    }
  }

  /// Replaces one instance with an edited copy.
  ///
  /// The id is the directory name and is never changed here: an edit that
  /// rewrites the identity would orphan the instance's files. The caller passes
  /// the already-edited value so this stays a single write of the whole list,
  /// which is the only atomic thing the store offers.
  Future<void> update(Instance instance) async {
    final existing = ready?.instances ?? const <Instance>[];
    if (!existing.any((i) => i.id == instance.id)) return;
    await _commit([
      for (final i in existing)
        if (i.id == instance.id) instance else i,
    ]);
  }

  Future<void> select(String? id) async {
    final current = ready;
    if (current == null) return;
    if (current.selectedId == id) return;
    state = InstanceListReady(
      current.instances,
      skipped: current.skipped,
      selectedId: id,
    );
  }

  /// Records a finished session: bumps the last-played stamp and adds to the
  /// total. Called with the *actual* session length, not the wall time since the
  /// window opened.
  Future<void> recordSession(String id, Duration session) async {
    final existing = ready?.instances ?? const <Instance>[];
    await _commit([
      for (final i in existing)
        if (i.id == id)
          i.copyWith(
            lastPlayedAt: DateTime.now(),
            totalPlaytime: i.totalPlaytime + session,
          )
        else
          i,
    ]);
  }
}

final instanceListProvider =
    NotifierProvider<InstanceListNotifier, InstanceListState>(
      InstanceListNotifier.new,
    );

/// The content-folder scan, injectable.
///
/// The section that uses it is in the instance page, and a widget test has no way
/// to let real directory IO complete inside the fake-async zone - so the scan is a
/// provider and a test answers it directly. Production reads the disk.
