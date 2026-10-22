import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/instance/instance.dart';

/// Where instances are read from and written to.
///
/// An interface so the app can be mounted in a test with no filesystem at all,
/// and so the eventual "import from another launcher" path can write through the
/// same seam.
abstract interface class InstanceStore {
  /// Every instance, in list order. Never throws for a damaged file: a corrupt
  /// entry is skipped and counted (see [lastSkipped]).
  Future<List<Instance>> load();

  Future<void> save(List<Instance> instances);

  /// How many entries were dropped by the most recent [load]. Zero on a clean
  /// read; the UI uses it to offer the user an explanation instead of a profile
  /// that silently vanished.
  int get lastSkipped;
}

/// The real store: one JSON file under the app's data directory.
///
/// Home directory resolution is injected (`DART_HOME` style) rather than calling
/// `path_provider` here, because `lib/core` and `lib/data` must stay testable
/// without platform channels.
class FileInstanceStore implements InstanceStore {
  FileInstanceStore({required this.root});

  /// The launcher's data root; instances live in `<root>/instances.json`.
  final Directory root;

  File get _file => File(p.join(root.path, 'instances.json'));

  @override
  int lastSkipped = 0;

  @override
  Future<List<Instance>> load() async {
    lastSkipped = 0;
    if (!await _file.exists()) return const [];
    final String text;
    try {
      text = await _file.readAsString();
    } on FileSystemException {
      // An unreadable file (permissions, a directory in its place) is not a
      // reason to refuse to start; the user just has no instances yet.
      lastSkipped = 1;
      return const [];
    }
    final decoded = decodeInstances(text);
    lastSkipped = decoded.skipped;
    return decoded.instances;
  }

  @override
  Future<void> save(List<Instance> instances) async {
    await root.create(recursive: true);
    // Write to a sibling temp file and rename: a crash mid-write must not leave a
    // truncated instances.json, which would read as "all instances are gone".
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(encodeInstances(instances), flush: true);
    await tmp.rename(_file.path);
  }
}

/// An in-memory store for tests and for a fresh install with no data dir yet.
class MemoryInstanceStore implements InstanceStore {
  MemoryInstanceStore([List<Instance> initial = const []])
    : _instances = List.of(initial);

  List<Instance> _instances;

  @override
  int lastSkipped = 0;

  @override
  Future<List<Instance>> load() async => List.of(_instances);

  @override
  Future<void> save(List<Instance> instances) async {
    _instances = List.of(instances);
  }
}
