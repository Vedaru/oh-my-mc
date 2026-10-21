/// The host environment a version is being resolved for.
///
/// Injected rather than read from the platform, so every rule branch can be
/// unit-tested for every OS/arch from one machine.
library;

enum HostOs {
  windows('windows'),
  osx('osx'),
  linux('linux');

  const HostOs(this.mcName);

  /// The name Mojang uses in `rules[].os.name`.
  final String mcName;

  static HostOs? fromMcName(String name) {
    for (final os in HostOs.values) {
      if (os.mcName == name) return os;
    }
    return null;
  }
}

enum HostArch {
  x86('x86'),
  x86_64('x86_64'),
  arm64('arm64');

  const HostArch(this.mcName);

  /// The name Mojang uses in `rules[].os.arch`.
  final String mcName;

  static HostArch? fromMcName(String name) {
    for (final a in HostArch.values) {
      if (a.mcName == name) return a;
    }
    return null;
  }

  /// Maps `dart:io`-style arch tokens ("x64", "aarch64") onto the rule vocabulary.
  static HostArch fromToken(String token) => switch (token.toLowerCase()) {
    'x64' || 'x86_64' || 'amd64' => HostArch.x86_64,
    'arm64' || 'aarch64' => HostArch.arm64,
    _ => HostArch.x86,
  };
}

/// Everything rule evaluation may consult.
class RuleContext {
  const RuleContext({
    required this.os,
    required this.arch,
    this.osVersion,
    this.features = const {},
  });

  final HostOs os;
  final HostArch arch;

  /// Dotted OS version, used by `rules[].os.versionRange` (26.x uses it to pick
  /// a GC flag on Windows 10 vs 11). Compared numerically segment by segment.
  final String? osVersion;

  /// Mojang feature flags, e.g. `is_demo_user`, `has_custom_resolution`,
  /// `has_quick_plays_support`.
  final Map<String, bool> features;

  bool feature(String name) => features[name] ?? false;

  RuleContext copyWith({Map<String, bool>? features}) => RuleContext(
    os: os,
    arch: arch,
    osVersion: osVersion,
    features: features ?? this.features,
  );
}
