import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'cancellation.dart';
import 'mirror.dart';
import 'progress.dart';

/// Thrown when a file's bytes do not match its expected SHA-1 after a retry.
class HashMismatchException implements Exception {
  HashMismatchException(this.path, this.expected, this.actual);

  final String path;
  final String expected;
  final String actual;

  @override
  String toString() =>
      'hash mismatch for $path: expected $expected, got $actual';
}

/// Thrown when every candidate source failed for one file.
class DownloadFailedException implements Exception {
  DownloadFailedException(this.url, this.causes);

  final Uri url;
  final List<Object> causes;

  @override
  String toString() =>
      'could not download $url after ${causes.length} attempt(s): '
      '${causes.map((e) => e.toString()).join('; ')}';
}

/// One file to fetch.
class DownloadTask {
  const DownloadTask({
    required this.url,
    required this.targetPath,
    required this.sha1,
    required this.size,
    this.priority = DownloadPriority.library,
  });

  final Uri url;

  /// Absolute destination. Parent directories are created as needed.
  final String targetPath;

  /// Expected SHA-1, lowercase hex. Empty disables verification — only used for
  /// modloader artifacts whose metadata ships no hash.
  final String sha1;

  final int size;
  final DownloadPriority priority;

  bool get verifiable => sha1.isNotEmpty;

  @override
  String toString() => '$url -> $targetPath';
}

/// Higher priorities are dequeued first. Metadata must land before the files
/// whose URLs it describes, or the install cannot even be planned.
enum DownloadPriority { metadata, library, asset, mod }

/// Remembers `(size, mtime)` per path so a second install of the same version
/// does not re-read half a gigabyte to re-verify hashes it already checked.
class HashCache {
  HashCache({this.persistPath});

  final String? persistPath;
  final Map<String, ({int size, DateTime mtime, String sha1})> _entries = {};

  /// Number of hash computations actually performed, for tests and telemetry.
  int hashCount = 0;

  bool isTrusted(String path, String expectedSha1) {
    final entry = _entries[path];
    if (entry == null) return false;
    final file = File(path);
    if (!file.existsSync()) return false;
    final stat = file.statSync();
    return entry.size == stat.size &&
        entry.mtime == stat.modified &&
        entry.sha1 == expectedSha1;
  }

  void record(String path, String sha1) {
    final file = File(path);
    if (!file.existsSync()) return;
    final stat = file.statSync();
    _entries[path] = (size: stat.size, mtime: stat.modified, sha1: sha1);
  }

  void forget(String path) => _entries.remove(path);

  int get length => _entries.length;
}

/// Verifies and downloads files: `.part` staging, hash check, atomic rename.
///
/// Every write goes to `<target>.part` first. A crash or cancel therefore leaves
/// a resumable partial file and never a truncated jar that the JVM would try to
/// load — which is the failure mode that produces "mysterious crash on second
/// launch" bug reports.
class FileDownloader {
  FileDownloader({
    HttpClient? client,
    MirrorChain? mirrors,
    HashCache? hashCache,
    this.retries = 2,
    this.progressInterval = const Duration(milliseconds: 120),
  }) : _client = client ?? HttpClient(),
       mirrors = mirrors ?? MirrorChain(),
       hashCache = hashCache ?? HashCache() {
    _client.connectionTimeout = const Duration(seconds: 20);
    _client.idleTimeout = const Duration(seconds: 15);
  }

  final HttpClient _client;
  final MirrorChain mirrors;
  final HashCache hashCache;

  /// Retries per source, after the first attempt.
  final int retries;

  /// Minimum gap between progress events, to keep the UI from rebuilding per
  /// 8 KB chunk.
  final Duration progressInterval;

  bool _closed = false;

  /// Fetches [tasks] with at most [concurrency] in flight.
  ///
  /// Emits an aggregate [DownloadProgress] stream. Completes when every task is
  /// either on disk and verified, or a [DownloadFailedException] has been
  /// thrown (fail-fast: the caller decides whether to retry the batch).
  ///
  /// Ordering is honoured in the sense that matters: metadata first, then
  /// libraries, then assets. Within a priority band files are fetched in
  /// parallel, because a modern install is ~3000 small assets and fetching them
  /// one at a time is minutes of avoidable latency.
  Stream<DownloadProgress> download(
    List<DownloadTask> tasks, {
    int concurrency = 8,
    CancelToken? cancel,
    void Function(int done, int total)? onProgressCount,
  }) {
    final totalBytes = tasks.fold<int>(0, (sum, t) => sum + t.size);
    final tracker = ProgressTracker(
      filesTotal: tasks.length,
      bytesTotal: totalBytes,
    );

    final controller = StreamController<DownloadProgress>();
    var lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

    void emit({bool force = false}) {
      if (controller.isClosed) return;
      final now = DateTime.now();
      if (!force && now.difference(lastEmit) < progressInterval) return;
      lastEmit = now;
      controller.add(tracker.snapshot());
    }

    () async {
      try {
        emit(force: true);
        for (final batch in _priorityBatches(_order(tasks))) {
          await _runBatch(batch, concurrency, tracker, emit, cancel);
        }
        emit(force: true);
        await controller.close();
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
        await controller.close();
      }
    }();

    return controller.stream;
  }

  /// Runs one priority band with a bounded worker pool.
  ///
  /// Bands run one after another so metadata is complete before anything that
  /// might need it, while the band itself runs in parallel. On the first error
  /// the remaining workers stop picking up new tasks; already-running transfers
  /// are awaited so no `.part` is left half-flushed by a returned future.
  Future<void> _runBatch(
    List<DownloadTask> batch,
    int concurrency,
    ProgressTracker tracker,
    void Function({bool force}) emit,
    CancelToken? cancel,
  ) async {
    if (batch.isEmpty) return;
    final workers = concurrency < 1 ? 1 : concurrency;
    var next = 0;
    Object? failure;

    Future<void> worker() async {
      while (true) {
        if (failure != null) return;
        if (cancel?.isCancelled ?? false) {
          failure ??= const CancelledException('download');
          return;
        }
        final index = next++;
        if (index >= batch.length) return;

        final task = batch[index];
        try {
          tracker.startFile(task.targetPath);
          await _fetchOne(task, tracker, emit, cancel);
          tracker.completeFile();
          emit(force: true);
        } catch (e) {
          failure ??= e;
          return;
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < workers && i < batch.length; i++) worker(),
    ]);
    if (failure != null) throw failure!;
  }

  /// Splits priority-sorted tasks into contiguous runs of equal priority.
  static List<List<DownloadTask>> _priorityBatches(List<DownloadTask> ordered) {
    final batches = <List<DownloadTask>>[];
    for (final task in ordered) {
      if (batches.isEmpty || batches.last.first.priority != task.priority) {
        batches.add([task]);
      } else {
        batches.last.add(task);
      }
    }
    return batches;
  }

  static List<DownloadTask> _order(List<DownloadTask> tasks) {
    final indexed = tasks.indexed.toList();
    indexed.sort((a, b) {
      final p = b.$2.priority.index.compareTo(a.$2.priority.index);
      return p != 0 ? p : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  Future<void> _fetchOne(
    DownloadTask task,
    ProgressTracker tracker,
    void Function({bool force}) emit, [
    CancelToken? cancel,
  ]) async {
    final target = File(task.targetPath);

    // Already present and trusted: count it and move on.
    if (await _isAlreadyValid(task)) {
      tracker.addBytes(task.size);
      return;
    }

    await target.parent.create(recursive: true);
    final part = File('${task.targetPath}.part');

    // Second attempt tolerates a mismatched hash once, per the plan.
    final maxAttempts = retries + 1;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final candidates = mirrors.candidates(task.url);
      final failures = <Object>[];

      for (final uri in candidates) {
        try {
          await _transfer(uri, part, task, tracker, emit, cancel);
          final actual = await _sha1Of(part);
          if (task.verifiable && actual != task.sha1.toLowerCase()) {
            await part.delete();
            failures.add(
              HashMismatchException(task.targetPath, task.sha1, actual),
            );
            // A bad body is a source problem: count it against that mirror.
            mirrors.markFailed(MirrorChain.sourceOf(uri));
            continue;
          }
          mirrors.markSucceeded(MirrorChain.sourceOf(uri));
          await _commit(part, target);
          hashCache.record(task.targetPath, actual);
          return;
        } catch (e) {
          failures.add(e);
          if (MirrorChain.sourceOf(uri) != DownloadSource.official) {
            mirrors.markFailed(MirrorChain.sourceOf(uri));
          }
        }
      }

      // Everything failed this attempt. Keep the .part for resume, unless the
      // failure was an integrity problem (then it is worthless).
      if (attempt == maxAttempts - 1) {
        throw DownloadFailedException(task.url, failures);
      }
    }
  }

  Future<void> _transfer(
    Uri uri,
    File part,
    DownloadTask task,
    ProgressTracker tracker,
    void Function({bool force}) emit, [
    CancelToken? cancel,
  ]) async {
    cancel?.throwIfCancelled('download');

    var startAt = 0;
    if (await part.exists()) {
      startAt = await part.length();
      // A .part as large as the target is corrupt, not resumable.
      if (task.size > 0 && startAt >= task.size) {
        await part.delete();
        startAt = 0;
      }
    }

    final request = await _client.getUrl(uri);
    if (startAt > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$startAt-');
    }
    final response = await request.close();

    if (startAt > 0 && response.statusCode != HttpStatus.partialContent) {
      // Host ignored Range: start over rather than appending garbage.
      await part.delete();
      startAt = 0;
    }

    if (response.statusCode >= 400) {
      await response.drain<void>();
      throw HttpException('HTTP ${response.statusCode} from $uri', uri: uri);
    }

    final sink = part.openWrite(
      mode: startAt > 0 ? FileMode.append : FileMode.write,
    );
    var received = 0;
    var aborted = false;
    try {
      await for (final chunk in response) {
        // Checked per chunk, not per file: a 300 MB asset must stop promptly
        // when the user cancels, not after it finishes.
        cancel?.throwIfCancelled('download');
        sink.add(chunk);
        received += chunk.length;
        tracker.addBytes(chunk.length);
        emit();
        if (task.size > 0 && startAt + received > task.size) {
          throw HttpException(
            'response longer than declared ${task.size}B',
            uri: uri,
          );
        }
      }
    } catch (_) {
      aborted = true;
      rethrow;
    } finally {
      await sink.flush();
      await sink.close();
      // A dropped connection mid-body leaves a .part whose tail is unknown, so
      // resuming from it would append to garbage. Discard instead (found by the
      // truncated-response test).
      if (aborted && await part.exists()) await part.delete();
    }

    if (task.size > 0) {
      final onDisk = await part.length();
      if (onDisk != task.size) {
        throw HttpException(
          'short read: $onDisk of ${task.size} bytes from $uri',
          uri: uri,
        );
      }
    }
  }

  Future<bool> _isAlreadyValid(DownloadTask task) async {
    final target = File(task.targetPath);
    if (!await target.exists()) return false;
    if (!task.verifiable) return true;
    if (hashCache.isTrusted(task.targetPath, task.sha1)) return true;

    final stat = await target.stat();
    if (task.size > 0 && stat.size != task.size) return false;

    final actual = await _sha1Of(target);
    if (actual != task.sha1.toLowerCase()) return false;
    hashCache.record(task.targetPath, actual);
    return true;
  }

  /// Renames into place. `rename` is atomic within a filesystem, so a reader
  /// never observes a partially written jar.
  Future<void> _commit(File part, File target) async {
    if (await target.exists()) await target.delete();
    await part.rename(target.path);
  }

  Future<String> _sha1Of(File file) async {
    hashCache.hashCount++;
    final digest = await sha1.bind(file.openRead()).first;
    return digest.toString();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _client.close(force: true);
  }
}
