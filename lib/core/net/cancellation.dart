import 'dart:async';

/// Thrown when work stops because the user cancelled the install.
///
/// Distinct from a download failure on purpose: the installer reports it as
/// "cancelled" and keeps the partial tree, while a failure is an error the user
/// must see and retry.
class CancelledException implements Exception {
  const CancelledException([this.stage]);

  /// Which stage noticed first, for the log.
  final String? stage;

  @override
  String toString() => stage == null ? 'cancelled' : 'cancelled during $stage';
}

/// A one-way cancellation flag shared by every stage of an install.
///
/// [whenCancelled] never completes with an error, so it is safe to `Future.any`
/// against and safe to leave unawaited. Stages are expected to check
/// [throwIfCancelled] at their own natural boundaries *and* to race long I/O
/// against [whenCancelled] — a stalled socket will otherwise ignore the flag
/// until the HTTP client's idle timeout fires, which looks like a hung UI.
class CancelToken {
  CancelToken();

  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  /// Completes (never errors) when [cancel] is called.
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  void throwIfCancelled([String? stage]) {
    if (isCancelled) throw CancelledException(stage);
  }

  /// Completes with [future]'s value, or throws [CancelledException] when the
  /// token fires first. [future] is not stopped — the caller must pass this
  /// token down so the underlying work can notice.
  Future<T> race<T>(Future<T> future, {String? stage}) async {
    if (isCancelled) throw CancelledException(stage);
    final result = await Future.any<Object?>([
      future,
      _cancelled.future.then<Object?>((_) => throw CancelledException(stage)),
    ]);
    return result as T;
  }
}
