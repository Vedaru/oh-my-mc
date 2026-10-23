import 'dart:io';

import 'package:path/path.dart' as p;

import '../net/cancellation.dart';
import 'mod_scanner.dart' show disabledSuffix;
import 'modrinth.dart';

/// What an install did, for the UI and the log.
class ModInstallOutcome {
  const ModInstallOutcome({
    required this.installed,
    required this.skipped,
    required this.failed,
  });

  /// File names written.
  final List<String> installed;

  /// File names already present, enabled or disabled.
  final List<String> skipped;

  /// File name → reason.
  final Map<String, String> failed;

  bool get isClean => failed.isEmpty;
}

/// Downloads resolved files into a directory - `mods/`, `resourcepacks/`,
/// `shaderpacks/`, `<world>/datapacks/`.
///
/// Deliberately dumb about *what* to install: `ModrinthClient.resolve` owns the
/// dependency graph and this only moves bytes, which is what makes the network part
/// testable against a local server.
class ModInstaller {
  ModInstaller({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  Future<ModInstallOutcome> install({
    required List<ModInstallPlan> plans,
    required String directory,
    CancelToken? cancel,
    void Function(int done, int total, String fileName)? onProgress,
  }) async {
    final dir = Directory(directory);
    await dir.create(recursive: true);

    final installed = <String>[];
    final skipped = <String>[];
    final failed = <String, String>{};

    for (var i = 0; i < plans.length; i++) {
      final plan = plans[i];
      cancel?.throwIfCancelled('mod download');
      final name = p.basename(plan.fileName);
      final target = p.join(directory, name);
      onProgress?.call(i, plans.length, name);

      // A mod that is present and disabled is still installed: writing a second
      // copy of `foo.jar` next to `foo.jar.disabled` is how a mods folder ends up
      // with two versions of the same mod fighting.
      if (File(target).existsSync() ||
          File('$target$disabledSuffix').existsSync()) {
        skipped.add(name);
        continue;
      }

      try {
        await _download(plan.file.url, target, cancel: cancel);
        installed.add(name);
      } on Object catch (e) {
        failed[name] = '$e';
        // A half-written jar must not be left behind: the loader would try to
        // read it and crash on startup.
        final part = File('$target.part');
        if (part.existsSync()) part.deleteSync();
      }
    }

    onProgress?.call(plans.length, plans.length, '');
    return ModInstallOutcome(
      installed: installed,
      skipped: skipped,
      failed: failed,
    );
  }

  /// Writes to `<name>.part` and renames, so an interrupted download never looks
  /// like an installed mod.
  Future<void> _download(
    String url,
    String target, {
    CancelToken? cancel,
  }) async {
    final uri = Uri.parse(url);
    final request = await _client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException('HTTP ${response.statusCode} from ${uri.host}');
    }
    final part = File('$target.part');
    final sink = part.openWrite();
    try {
      await response.pipe(sink);
    } finally {
      await sink.close();
    }
    cancel?.throwIfCancelled('mod download');
    await part.rename(target);
  }

  void close() => _client.close(force: true);
}
