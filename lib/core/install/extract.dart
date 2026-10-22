import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../net/cancellation.dart';

/// One entry that was written, for logging and for tests to assert on.
class ExtractedEntry {
  const ExtractedEntry({required this.relativePath, required this.bytes});

  final String relativePath;
  final int bytes;
}

/// Result of unpacking one native archive.
class ExtractResult {
  const ExtractResult({
    required this.archive,
    required this.entries,
    required this.skipped,
  });

  final String archive;

  /// Written files, relative to the destination directory.
  final List<ExtractedEntry> entries;

  /// Entries dropped because they matched an `extract.exclude` prefix, or were
  /// directories.
  final List<String> skipped;
}

/// One archive to unpack.
class NativeArchiveSpec {
  const NativeArchiveSpec({
    required this.file,
    required this.label,
    this.exclude = const [],
  });

  /// Path to the archive already on disk.
  final String file;

  /// Display name for the log (`group:artifact:version`).
  final String label;

  /// `extract.exclude` prefixes from the version JSON.
  final List<String> exclude;
}

/// Unpacks native archives into [destination].
///
/// Three properties are load-bearing, each for a specific real failure:
///
/// * **Path traversal is refused.** A zip entry named `../../.bashrc` or an
///   absolute path would otherwise write outside the game directory. Mojang
///   archives never contain these, which is exactly why a poisoned mirror could
///   exploit it silently.
/// * **The swap is atomic.** Entries go to a sibling temp directory, renamed into
///   place only when every archive unpacked. A cancel or crash therefore never
///   leaves a natives dir that is *present but incomplete* — the state that
///   surfaces as an unexplained `UnsatisfiedLinkError` instead of "reinstall".
/// * **It is idempotent.** Re-running replaces the directory rather than merging
///   into it, so a broken install heals instead of accumulating stale `.so` files.
Future<List<ExtractResult>> extractNatives({
  required List<NativeArchiveSpec> archives,
  required String destination,
  CancelToken? cancel,
}) async {
  final dest = p.normalize(p.absolute(destination));
  final staging = '$dest.tmp';
  final stagingDir = Directory(staging);

  // A leftover staging dir from a killed run would poison the swap.
  if (stagingDir.existsSync()) stagingDir.deleteSync(recursive: true);
  await stagingDir.create(recursive: true);

  final results = <ExtractResult>[];

  try {
    for (final archive in archives) {
      cancel?.throwIfCancelled('natives');
      results.add(
        await _extractOne(
          spec: archive,
          destination: staging,
          destinationRoot: staging,
          cancel: cancel,
        ),
      );
    }
    cancel?.throwIfCancelled('natives');

    final destDir = Directory(dest);
    if (destDir.existsSync()) destDir.deleteSync(recursive: true);
    await stagingDir.rename(dest);
    return results;
  } catch (_) {
    if (stagingDir.existsSync()) stagingDir.deleteSync(recursive: true);
    rethrow;
  }
}

Future<ExtractResult> _extractOne({
  required NativeArchiveSpec spec,
  required String destination,
  required String destinationRoot,
  CancelToken? cancel,
}) async {
  final file = File(spec.file);
  if (!file.existsSync()) {
    throw FileSystemException('native archive is missing', spec.file);
  }

  final bytes = await file.readAsBytes();
  cancel?.throwIfCancelled('natives');

  final Archive parsed;
  try {
    parsed = ZipDecoder().decodeBytes(bytes);
  } on Object catch (e) {
    throw FormatException(
      'native archive ${spec.label} is not a readable zip: $e',
    );
  }

  // `ZipDecoder` answers an empty Archive for bytes that are not a zip at all
  // (observed with a truncated download and with an HTML mirror error page), so
  // without these two checks a corrupt archive produces a *silently empty*
  // natives directory and the install reports success.
  if (!_hasZipSignature(bytes)) {
    throw FormatException(
      'native archive ${spec.label} is not a zip (no PK header)',
    );
  }
  if (parsed.files.isEmpty) {
    throw FormatException('native archive ${spec.label} contains no entries');
  }

  final written = <ExtractedEntry>[];
  final skipped = <String>[];

  for (final entry in parsed.files) {
    if (!entry.isFile) {
      skipped.add(entry.name);
      continue;
    }
    final name = safeRelativeEntryName(entry.name, spec.label);
    if (isExcluded(name, spec.exclude)) {
      skipped.add(entry.name);
      continue;
    }

    final target = p.normalize(p.join(destination, name));
    // Defence in depth: the name is already known-relative, but a normalised
    // join is the only thing that actually bounds the write.
    if (target != destinationRoot && !p.isWithin(destinationRoot, target)) {
      throw FormatException(
        'native archive ${spec.label} tried to write outside the target: '
        '${entry.name}',
      );
    }

    final data = entry.readBytes();
    if (data == null) {
      throw FormatException(
        'native archive ${spec.label} has an unreadable entry: ${entry.name}',
      );
    }
    final out = File(target);
    await out.parent.create(recursive: true);
    await out.writeAsBytes(data, flush: false);
    written.add(ExtractedEntry(relativePath: name, bytes: data.length));
    cancel?.throwIfCancelled('natives');
  }

  return ExtractResult(archive: spec.label, entries: written, skipped: skipped);
}

/// True when [bytes] start with a zip local-file header or an empty-archive
/// end-of-central-directory record.
bool _hasZipSignature(List<int> bytes) {
  if (bytes.length < 4) return false;
  // "PK\x03\x04" local file, "PK\x05\x06" empty archive.
  return bytes[0] == 0x50 &&
      bytes[1] == 0x4B &&
      ((bytes[2] == 0x03 && bytes[3] == 0x04) ||
          (bytes[2] == 0x05 && bytes[3] == 0x06));
}

/// Rejects absolute paths and any entry that escapes its root.
///
/// Separators are unified first: zips written on Windows use `\`, and `path`'s
/// `normalize` on Linux would treat that as a literal character in a filename —
/// producing a file called `a\b.so` rather than a nested file.
String safeRelativeEntryName(String entryName, String label) {
  final unified = entryName.replaceAll('\\', '/');
  if (unified.isEmpty) {
    throw FormatException('native archive $label has an empty entry name');
  }
  if (p.posix.isAbsolute(unified)) {
    throw FormatException(
      'native archive $label has an absolute path entry: $entryName',
    );
  }
  if (RegExp(r'^[A-Za-z]:').hasMatch(unified)) {
    throw FormatException(
      'native archive $label has a drive-letter entry: $entryName',
    );
  }

  final normalised = p.posix.normalize(unified);
  if (normalised == '..' || normalised.startsWith('../')) {
    throw FormatException(
      'native archive $label traverses outside the target: $entryName',
    );
  }
  return normalised;
}

/// True when [name] matches any of the model's `extract.exclude` prefixes.
///
/// Case-insensitive because archives have been observed to mix case, and because
/// the cost of excluding one entry too many is zero while the cost of shipping
/// `META-INF/services` into a natives dir is a confusing log line.
bool isExcluded(String name, List<String> exclude) {
  if (exclude.isEmpty) return false;
  final lower = name.toLowerCase();
  for (final prefix in exclude) {
    final cleaned = prefix
        .replaceAll('\\', '/')
        .toLowerCase()
        .replaceFirst(RegExp(r'/+$'), '');
    if (cleaned.isEmpty) continue;
    // A bare name matches itself as well as anything under it: an archive can
    // carry `META-INF` as a zero-length directory entry, and `META-INF/x`.
    if (lower == cleaned || lower.startsWith('$cleaned/')) return true;
  }
  return false;
}
