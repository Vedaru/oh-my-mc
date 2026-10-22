import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/data/instance_providers.dart';
import 'package:oh_my_mc/data/instance_store.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:path/path.dart' as p;

/// Deleting an instance has to delete its folder, and has to refuse to delete
/// anyone else's.
///
/// The containment test is not theoretical: `id` doubles as the directory name
/// and comes out of `instances.json`, which a user can hand-edit.
void main() {
  late Directory data;
  late LauncherPaths paths;

  setUp(() async {
    data = await Directory.systemTemp.createTemp('instance_delete_test');
    paths = LauncherPaths(
      data: data,
      game: Directory(p.join(data.path, 'game')),
    );
  });

  tearDown(() async {
    if (await data.exists()) await data.delete(recursive: true);
  });

  Instance sample(String id) => Instance(id: id, name: id, versionId: '1.20.1');

  Future<ProviderContainer> containerWith(List<Instance> instances) async {
    final container = ProviderContainer(
      overrides: [
        instanceStoreProvider.overrideWith(
          (ref) => MemoryInstanceStore(instances),
        ),
        launcherPathsProvider.overrideWithValue(paths),
      ],
    );
    addTearDown(container.dispose);
    // The notifier loads asynchronously from `build`, so wait for the list
    // before asking it to remove anything.
    await container.read(instanceListProvider.notifier).refresh();
    return container;
  }

  /// A populated instance folder: one file, so the delete is not trivially
  /// "remove an empty directory".
  Future<File> seedFiles(String id) async {
    final directory = Directory(p.join(paths.instanceRoot.path, id));
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, 'minecraft', 'options.txt'));
    await file.parent.create(recursive: true);
    await file.writeAsString('fov:0.5\n');
    return file;
  }

  test('remove(deleteFiles: true) takes the directory with it', () async {
    final file = await seedFiles('demo');
    final container = await containerWith([sample('demo')]);

    final deleted = await container
        .read(instanceListProvider.notifier)
        .remove('demo', deleteFiles: true);

    expect(deleted, isTrue);
    expect(file.existsSync(), isFalse);
    expect(
      Directory(p.join(paths.instanceRoot.path, 'demo')).existsSync(),
      isFalse,
    );
    expect(
      (container.read(instanceListProvider) as InstanceListReady).instances,
      isEmpty,
    );
  });

  test('remove() without deleteFiles keeps the folder', () async {
    final file = await seedFiles('demo');
    final container = await containerWith([sample('demo')]);

    await container.read(instanceListProvider.notifier).remove('demo');

    expect(file.existsSync(), isTrue);
    // Stray files are the documented trade-off; a listed instance pointing at a
    // missing folder is not.
    expect(
      (container.read(instanceListProvider) as InstanceListReady).instances,
      isEmpty,
    );
  });

  test('an id that escapes the instances root deletes nothing', () async {
    // A hand-edited file, not something the UI can produce.
    final outside = File(p.join(data.path, 'keep-me.txt'));
    await outside.writeAsString('precious');
    final container = await containerWith([sample('../..')]);

    final deleted = await container
        .read(instanceListProvider.notifier)
        .remove('../..', deleteFiles: true);

    expect(deleted, isFalse);
    expect(outside.existsSync(), isTrue);
    expect(data.existsSync(), isTrue);
    // The bogus entry still leaves the list: keeping it would leave the user
    // unable to remove it at all.
    expect(
      (container.read(instanceListProvider) as InstanceListReady).instances,
      isEmpty,
    );
  });

  test('a missing directory is a success, not a failure', () async {
    final container = await containerWith([sample('never-launched')]);

    expect(
      await container
          .read(instanceListProvider.notifier)
          .remove('never-launched', deleteFiles: true),
      isTrue,
    );
  });

  test('removes the selection rather than stranding it', () async {
    await seedFiles('a');
    await seedFiles('b');
    final container = await containerWith([sample('a'), sample('b')]);
    await container.read(instanceListProvider.notifier).select('a');

    await container
        .read(instanceListProvider.notifier)
        .remove('a', deleteFiles: true);

    final state = container.read(instanceListProvider) as InstanceListReady;
    expect(state.selectedId, 'b');
  });

  test('a slow refresh cannot undo a delete that happened meanwhile', () async {
    // The real store reads a file, so `load` always crosses an await; a fake that
    // resolves in the same microtask would hide the race this pins.
    final store = _SlowStore([sample('demo')]);
    final container = ProviderContainer(
      overrides: [
        instanceStoreProvider.overrideWith((ref) => store),
        launcherPathsProvider.overrideWithValue(paths),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(instanceListProvider.notifier);

    final pendingRefresh = notifier.refresh();
    await notifier.remove('demo');
    store.release();
    await pendingRefresh;

    expect(
      (container.read(instanceListProvider) as InstanceListReady).instances,
      isEmpty,
      reason: 'the read started before the delete and must not resurrect it',
    );
  });
}

/// A store whose `load` blocks until [release], so a read can be made to finish
/// after a write.
class _SlowStore implements InstanceStore {
  _SlowStore(this._instances);

  List<Instance> _instances;
  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  int lastSkipped = 0;

  @override
  Future<List<Instance>> load() async {
    final snapshot = List.of(_instances);
    await _gate.future;
    return snapshot;
  }

  @override
  Future<void> save(List<Instance> instances) async {
    _instances = List.of(instances);
  }
}
