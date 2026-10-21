import 'host.dart';
import 'rules.dart';
import 'version_json.dart';
import 'version_resolver.dart';

/// A library file that must exist on disk before launch.
class ResolvedFile {
  const ResolvedFile({
    required this.path,
    required this.url,
    required this.sha1,
    required this.size,
  });

  final String path;
  final String url;
  final String sha1;
  final int size;
}

/// The outcome of turning a version's `libraries` into a classpath and a set of
/// native archives, for one concrete host.
class LibraryGraph {
  const LibraryGraph({
    required this.classpath,
    required this.natives,
    required this.jars,
    required this.skipped,
  });

  /// Maven-relative paths, in classpath order (metadata order, deduped).
  final List<ResolvedFile> classpath;

  /// Native archives to unpack, with the extract-exclude prefixes to honour.
  final List<NativeArchive> natives;

  /// Every file that must be downloaded, classpath and natives included.
  final List<ResolvedFile> jars;

  /// Entries dropped because their rules excluded this host. Kept for the
  /// "why is this jar missing" question that always comes up in bug reports.
  final List<String> skipped;

  List<String> get classpathPaths => [for (final j in classpath) j.path];
}

class NativeArchive {
  const NativeArchive({required this.file, required this.exclude});

  final ResolvedFile file;
  final List<String> exclude;
}

/// Builds the classpath/natives view for [host].
///
/// Order matters: metadata order is preserved because JVM classpath resolution
/// is first-wins, and modloaders depend on their patched libraries appearing
/// before the vanilla ones for the same artifact.
LibraryGraph buildLibraryGraph(
  VersionJson version,
  RuleContext host, {
  Map<String, bool> features = const {},
}) {
  final ctx = host.copyWith(features: features);
  final allowed = <Library>[];
  final skipped = <String>[];

  for (final lib in version.libraries) {
    if (ruleAllows(lib.rules, ctx)) {
      allowed.add(lib);
    } else {
      skipped.add(lib.name);
    }
  }

  // Dedupe after filtering so per-platform duplicates collapse to the entry
  // that actually applies here (1.12.2 ships two lwjgl-platform entries).
  final effective = dedupeLibraries(allowed);

  final classpath = <ResolvedFile>[];
  final natives = <NativeArchive>[];
  final jars = <ResolvedFile>[];
  final seenNatives = <String>{};

  for (final lib in effective) {
    final artifact = lib.downloads?.artifact;
    if (artifact != null && artifact.path.isNotEmpty) {
      final file = ResolvedFile(
        path: artifact.path,
        url: artifact.url,
        sha1: artifact.sha1,
        size: artifact.size,
      );
      classpath.add(file);
      jars.add(file);
    }

    final nativesMap = lib.natives;
    if (nativesMap == null) continue;

    final classifier = nativesMap[ctx.os.mcName];
    if (classifier == null) continue;

    // Legacy metadata interpolates ${arch}; on 64-bit hosts that is "64".
    final expanded = classifier.replaceAll(
      r'${arch}',
      ctx.arch == HostArch.x86 ? '32' : '64',
    );

    final nat = lib.downloads?.classifiers[expanded];
    if (nat == null || nat.path.isEmpty) continue;
    if (!seenNatives.add(nat.path)) continue;

    final archive = NativeArchive(
      file: ResolvedFile(
        path: nat.path,
        url: nat.url,
        sha1: nat.sha1,
        size: nat.size,
      ),
      exclude: lib.extract?.exclude ?? const [],
    );
    natives.add(archive);
    jars.add(archive.file);
  }

  return LibraryGraph(
    classpath: classpath,
    natives: natives,
    jars: jars,
    skipped: skipped,
  );
}
