import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

import 'host.dart';

/// The host this process is running on, for rule evaluation and install planning.
///
/// Separate from `host.dart` on purpose: that file is a pure value type so every
/// rule branch is testable for every OS/arch from one machine. This is the one
/// place that asks the platform, and it is kept thin enough to read at a glance.
///
/// The arch comes from `dart:ffi`'s [Abi] rather than `Platform.version`
/// substring matching: the version string is not specified to contain an arch
/// token, and an x64 machine that reports "arm64" somewhere in its kernel build
/// string would silently get x64 natives on an ARM host (or the reverse), which
/// fails as an obscure `UnsatisfiedLinkError` much later.
RuleContext localRuleContext({Map<String, bool> features = const {}}) =>
    RuleContext(
      os: localHostOs,
      arch: localHostArch,
      // Only Windows rules use `versionRange` (a GC flag on 10 vs 11), and
      // Mojang's ranges are compared against the *OS* version, which Dart does
      // not expose. Leaving it null makes such a rule not match, which is the
      // conservative choice: the flag is an optimization, not a requirement.
      osVersion: null,
      features: features,
    );

HostOs get localHostOs {
  if (Platform.isWindows) return HostOs.windows;
  if (Platform.isMacOS) return HostOs.osx;
  return HostOs.linux;
}

HostArch get localHostArch => switch (Abi.current()) {
  Abi.androidArm64 ||
  Abi.iosArm64 ||
  Abi.linuxArm64 ||
  Abi.macosArm64 ||
  Abi.windowsArm64 ||
  Abi.fuchsiaArm64 => HostArch.arm64,
  Abi.androidArm || Abi.iosArm || Abi.linuxArm => HostArch.arm64,
  Abi.androidX64 ||
  Abi.iosX64 ||
  Abi.linuxX64 ||
  Abi.macosX64 ||
  Abi.windowsX64 ||
  Abi.fuchsiaX64 => HostArch.x86_64,
  _ => HostArch.x86,
};
