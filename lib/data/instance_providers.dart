import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/instance/instance.dart';
import 'instance_store.dart';

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

  Future<void> refresh() async {
    try {
      final instances = await _store.load();
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

  Future<void> remove(String id) async {
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
