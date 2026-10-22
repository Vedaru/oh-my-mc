import 'dart:convert';
import 'dart:io';

import '../mc/install_plan.dart';

/// Marks a version directory whose install did not finish.
///
/// A launcher can be killed at any moment - a crash, the machine sleeping and the
/// process being reaped, a `pkill` while a build is swapped in. The partial tree
/// it leaves behind is *indistinguishable from a complete one* to the check that
/// matters, `versions/<id>/<id>.json`, because the JSON is written first and the
/// libraries last. Without a marker:
///
/// * the download page counts the version as installed, so its row stops offering
///   the install;
/// * the launch path can only refuse ("67 files are missing"), with nothing to
///   click;
/// * and the repair affordance lives in `InstallDone(problemCount > 0)`, a state
///   only a *finished* install reaches - so an interrupted install has no repair
///   entry anywhere, ever.
///
/// One sentinel file turns that into "click install again": the downloader skips
/// what is already on disk by hash and the install resumes where it stopped.
class InstallJournal {
  const InstallJournal._();

  /// Hidden, and inside the version directory so it travels with the install and
  /// disappears with it.
  static const markerName = '.installing';

  static File markerAt(GamePaths paths, String versionId) =>
      File('${paths.versionDir(versionId)}/$markerName');

  static bool isIncomplete(GamePaths paths, String versionId) =>
      markerAt(paths, versionId).existsSync();

  /// Records the start of an install.
  ///
  /// Best effort on purpose: failing to *mark* an install is not a reason to
  /// refuse to install, so a read-only or full disk still gets a real attempt.
  static Future<void> begin(
    GamePaths paths,
    String versionId, {
    String? stage,
  }) async {
    try {
      final marker = markerAt(paths, versionId);
      await marker.parent.create(recursive: true);
      await marker.writeAsString(
        jsonEncode({
          'versionId': versionId,
          'startedAt': DateTime.now().toUtc().toIso8601String(),
          'stage': ?stage,
        }),
        flush: true,
      );
    } on FileSystemException {
      // See above.
    }
  }

  /// Clears the marker. Called only when verification found nothing missing, so
  /// "no marker" means "the tree is complete", not "the process reached the end".
  static Future<void> finish(GamePaths paths, String versionId) async {
    try {
      final marker = markerAt(paths, versionId);
      if (marker.existsSync()) await marker.delete();
    } on FileSystemException {
      // A marker that cannot be deleted costs one re-verify, not a broken install.
    }
  }

  /// When the interrupted install started, for "interrupted 2 hours ago".
  static DateTime? startedAt(GamePaths paths, String versionId) {
    try {
      final decoded = jsonDecode(markerAt(paths, versionId).readAsStringSync());
      final started = decoded is Map ? decoded['startedAt'] : null;
      return started is String ? DateTime.tryParse(started) : null;
    } on Object {
      // A truncated marker is still a marker: it says "not finished".
      return null;
    }
  }
}
