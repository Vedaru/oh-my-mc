import 'host.dart';
import 'library_graph.dart';
import 'version_json.dart';

/// Compatibility problems that stop a version from launching on a given host,
/// detected from metadata alone so the UI can explain them before downloading
/// 400 MB and failing at JVM start.
class LaunchBlocker {
  const LaunchBlocker({
    required this.code,
    required this.message,
    required this.remedy,
  });

  final BlockerCode code;
  final String message;

  /// What the user can actually do about it.
  final String remedy;

  @override
  String toString() => '$code: $message ($remedy)';
}

enum BlockerCode {
  /// LWJGL 2 ships x86/x86_64 natives only. Minecraft before 1.13 therefore
  /// cannot run on Apple Silicon, which is why every launcher ships Rosetta or
  /// an arm64 workaround for it.
  lwjgl2OnArm64Mac,

  /// A library the version needs has no artifact for this platform at all.
  missingNativeForHost,

  /// `rules` excluded every entry of a required library.
  allLibrariesFiltered,

  /// The version needs a newer Java than the one found.
  javaTooOld,
}

/// Detects metadata-level blockers for [version] on [host].
///
/// macOS arm64 is the case that actually happens in the wild: there are no
/// arm64 LWJGL 2 natives, so the options are an x86_64 JVM under Rosetta 2, or
/// refusing with a clear message. We report it and let the caller decide.
List<LaunchBlocker> detectBlockers(
  VersionJson version,
  LibraryGraph graph,
  HostOs hostOs,
  HostArch hostArch,
) {
  final blockers = <LaunchBlocker>[];

  // LWJGL 2 lives at group `org.lwjgl.lwjgl`; LWJGL 3 is `org.lwjgl`. Matching
  // on the *path* is wrong because both produce `org/lwjgl/lwjgl/...` (LWJGL 3's
  // artifact `lwjgl` lands at `org/lwjgl/lwjgl/3.4.3/`), which would flag every
  // modern version as unlaunchable on Apple Silicon.
  final lwjgl2 = version.libraries.where(
    (l) => l.group == 'org.lwjgl.lwjgl' && l.artifact.startsWith('lwjgl'),
  );

  if (hostOs == HostOs.osx && hostArch == HostArch.arm64 && lwjgl2.isNotEmpty) {
    blockers.add(
      LaunchBlocker(
        code: BlockerCode.lwjgl2OnArm64Mac,
        message:
            'This version uses LWJGL 2, which has no arm64 natives. '
            'It cannot start on Apple Silicon natively.',
        remedy: 'Run it under Rosetta 2 with an x86_64 Java 8 runtime, or use 1.13+.',
      ),
    );
  }

  final needsNatives =
      version.libraries.any(
        (l) => l.natives != null && l.natives!.isNotEmpty,
      ) ||
      version.libraries.any(
        (l) => l.downloads?.classifiers.isNotEmpty ?? false,
      );

  if (needsNatives && graph.natives.isEmpty) {
    blockers.add(
      LaunchBlocker(
        code: BlockerCode.missingNativeForHost,
        message:
            'The version declares native libraries but none apply to '
            '${hostOs.mcName}/${hostArch.mcName}.',
        remedy: 'This platform is not supported by that version.',
      ),
    );
  }

  if (graph.classpath.isEmpty) {
    blockers.add(
      LaunchBlocker(
        code: BlockerCode.allLibrariesFiltered,
        message: 'Every library was excluded by its rules for this platform.',
        remedy: 'Check the version JSON; the rules may be malformed.',
      ),
    );
  }

  return blockers;
}

/// Whether [availableJavaMajor] satisfies the version's declared requirement.
LaunchBlocker? checkJava(VersionJson version, int? availableJavaMajor) {
  final required = version.javaVersion?.majorVersion;
  if (required == null || availableJavaMajor == null) return null;
  if (availableJavaMajor >= required) return null;
  return LaunchBlocker(
    code: BlockerCode.javaTooOld,
    message:
        'This version needs Java $required, but Java $availableJavaMajor was found.',
    remedy: 'Install Java $required (the launcher can download it).',
  );
}
