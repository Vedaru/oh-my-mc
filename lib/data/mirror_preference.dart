import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/net/mirror.dart';
import '../app/providers.dart';
import 'settings.dart';

/// Turns the source preference into an order for [MirrorChain].
///
/// [measuredFastest] is what the last speed test found (`settings.fastestSource`),
/// which is what `auto` means.
///
/// The loser stays in the list on purpose: a preference is a starting point, not a
/// promise. `MirrorChain` already trips a source out after three consecutive
/// failures, so a user who picked the wrong one is slowed down, not blocked.
List<DownloadSource> mirrorOrderFor(
  SourcePreference preference, {
  DownloadSource? measuredFastest,
}) => switch (preference) {
  SourcePreference.official => const [
    DownloadSource.official,
    DownloadSource.bmclapi,
  ],
  SourcePreference.bmclapi => const [
    DownloadSource.bmclapi,
    DownloadSource.official,
  ],
  // Auto: the measured winner first, then the other. With no measurement yet the
  // official CDN goes first - it is the one that is correct by definition.
  SourcePreference.auto =>
    measuredFastest == DownloadSource.bmclapi
        ? const [DownloadSource.bmclapi, DownloadSource.official]
        : const [DownloadSource.official, DownloadSource.bmclapi],
};

/// Maps a speed-test sample name onto the source it measured.
DownloadSource? sourceOfMirrorSample(String name) => switch (name) {
  'Mojang' => DownloadSource.official,
  'BMCLAPI' => DownloadSource.bmclapi,
  _ => null,
};

/// The chain every installer uses.
///
/// One provider so a preference change applies to the next install without any
/// screen having to pass it down: the installer already takes a `MirrorChain`.
final mirrorChainProvider = Provider<MirrorChain>((ref) {
  final settings = ref.watch(appSettingsProvider);
  return MirrorChain(
    order: mirrorOrderFor(
      settings.downloadSource,
      measuredFastest: switch (settings.fastestSource) {
        'bmclapi' => DownloadSource.bmclapi,
        'official' => DownloadSource.official,
        _ => null,
      },
    ),
  );
});
