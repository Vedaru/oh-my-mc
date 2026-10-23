import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/data/instance_cloner.dart';
import 'package:oh_my_mc/data/instance_providers.dart';
import 'package:oh_my_mc/data/instance_store.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late ProviderContainer container;
  late InstanceListNotifier instances;
  late LauncherPaths paths;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('instance-clone');
    paths = LauncherPaths(data: tmp, game: Directory(p.join(tmp.path, 'game')));
    container = ProviderContainer(
      overrides: [
        instanceStoreProvider.overrideWith((ref) => MemoryInstanceStore()),
        launcherPathsProvider.overrideWithValue(paths),
      ],
    );
    instances = container.read(instanceListProvider.notifier);
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() async {
    container.dispose();
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('a clone copies the game directory and its settings', () async {
    final source = await instances.create(
      name: 'Survival',
      versionId: '1.20.1',
      loader: LoaderKind.fabric,
      loaderVersion: '0.16.9',
    );
    await instances.update(
      source.copyWith(
        memoryMb: 6144,
        gameArgs: const ['--demo'],
        fullscreen: false,
      ),
    );
    final from = Directory(paths.gamePathsFor(source).root);
    Directory(p.join(from.path, 'mods')).createSync(recursive: true);
    File(p.join(from.path, 'mods/sodium.jar')).writeAsStringSync('jar');
    Directory(p.join(from.path, 'saves/world')).createSync(recursive: true);
    File(p.join(from.path, 'saves/world/level.dat')).writeAsStringSync('world');
    // Session noise must not follow the world into the copy.
    Directory(p.join(from.path, 'logs')).createSync();
    File(p.join(from.path, 'logs/latest.log')).writeAsStringSync('crash');

    final clone = await const InstanceCloner().clone(
      source: source,
      instances: instances,
      paths: paths,
    );

    final to = paths.gamePathsFor(clone).root;
    expect(clone.id, isNot(source.id));
    expect(clone.name, 'Survival (copy)');
    expect(clone.versionId, '1.20.1');
    expect(clone.loader, LoaderKind.fabric);
    expect(clone.memoryMb, 6144);
    expect(clone.gameArgs, ['--demo']);
    expect(File(p.join(to, 'mods/sodium.jar')).readAsStringSync(), 'jar');
    expect(
      File(p.join(to, 'saves/world/level.dat')).readAsStringSync(),
      'world',
    );
    expect(File(p.join(to, 'logs/latest.log')).existsSync(), isFalse);
    // The original is untouched.
    expect(File(p.join(from.path, 'mods/sodium.jar')).existsSync(), isTrue);
  });

  test('cloning an instance with no directory yet still creates one', () async {
    final source = await instances.create(name: 'Empty', versionId: '1.20.1');

    final clone = await const InstanceCloner().clone(
      source: source,
      instances: instances,
      paths: paths,
    );

    expect(
      Directory(paths.gamePathsFor(clone).root).existsSync(),
      isFalse,
      reason: 'nothing to copy, so no directory is invented',
    );
    expect(
      (container.read(instanceListProvider) as InstanceListReady).instances,
      hasLength(2),
    );
  });
}
