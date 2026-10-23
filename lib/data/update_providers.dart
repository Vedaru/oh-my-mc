import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/version.dart';
import '../core/update/launcher_update.dart';

/// Whether a newer release of the launcher exists.
///
/// Asked once per session, in the background: `null` covers "no update", "no network"
/// and "GitHub said nothing useful" alike, because the launch page has nothing to show
/// in any of those cases.
final launcherUpdateProvider = FutureProvider<LauncherUpdate?>(
  (ref) => const LauncherUpdateChecker().check(currentVersion: appVersion),
);
