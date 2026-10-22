import 'dart:io';

import 'package:crypto/crypto.dart';

import '../mc/install_plan.dart';

/// One reason an install is not usable.
class VerifyProblem {
  const VerifyProblem({
    required this.path,
    required this.reason,
    this.expected,
    this.actual,
  });

  final String path;
  final VerifyReason reason;
  final String? expected;
  final String? actual;

  @override
  String toString() =>
      '$reason: $path${expected == null ? '' : ' (expected $expected, got '
                '$actual)'}';
}

enum VerifyReason {
  /// The file the plan lists is not on disk.
  missing,

  /// Present, but its bytes do not match the metadata hash.
  corrupt,

  /// Present with the wrong size — usually a truncated download from an older
  /// launcher version, so it is distinguished from a size-correct hash mismatch.
  wrongSize,
}

class VerifyReport {
  const VerifyReport({
    required this.checkedFiles,
    required this.checkedBytes,
    required this.problems,
  });

  final int checkedFiles;
  final int checkedBytes;
  final List<VerifyProblem> problems;

  bool get isComplete => problems.isEmpty;

  List<String> get missing => [
    for (final p in problems)
      if (p.reason == VerifyReason.missing) p.path,
  ];

  @override
  String toString() => isComplete
      ? 'install complete ($checkedFiles files)'
      : '${problems.length} problem(s): '
            '${problems.take(5).map((p) => p.path).join(', ')}'
            '${problems.length > 5 ? ' …' : ''}';
}

/// Checks every file the plan requires, without fixing anything.
///
/// Returns problems rather than throwing: "3 files missing" is a normal answer
/// the UI shows with a Repair button, not an exception. Hashing is opt-out
/// ([checkHashes]) because verifying a full modern install reads several
/// gigabytes, which is far too slow to do on every launch — size-only is enough
/// to catch the truncation that actually happens.
Future<VerifyReport> verifyInstall(
  InstallPlan plan, {
  bool checkHashes = false,
  void Function(int done, int total)? onProgress,
}) async {
  var checkedFiles = 0;
  var checkedBytes = 0;
  final problems = <VerifyProblem>[];

  for (final task in plan.tasks) {
    final file = File(task.targetPath);
    if (!file.existsSync()) {
      problems.add(
        VerifyProblem(path: task.targetPath, reason: VerifyReason.missing),
      );
      continue;
    }

    final length = await file.length();
    checkedFiles++;
    checkedBytes += length;

    if (task.size > 0 && length != task.size) {
      problems.add(
        VerifyProblem(
          path: task.targetPath,
          reason: VerifyReason.wrongSize,
          expected: '${task.size}',
          actual: '$length',
        ),
      );
      continue;
    }

    if (checkHashes && task.verifiable) {
      final actual = (await sha1.bind(file.openRead()).first).toString();
      if (actual != task.sha1.toLowerCase()) {
        problems.add(
          VerifyProblem(
            path: task.targetPath,
            reason: VerifyReason.corrupt,
            expected: task.sha1,
            actual: actual,
          ),
        );
      }
    }

    onProgress?.call(checkedFiles, plan.tasks.length);
  }

  return VerifyReport(
    checkedFiles: checkedFiles,
    checkedBytes: checkedBytes,
    problems: problems,
  );
}
