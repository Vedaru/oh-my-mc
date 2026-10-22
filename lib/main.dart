import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app_root.dart';
import 'app/providers.dart';
import 'app/router.dart';
import 'core/instance/instance.dart';
import 'core/launch/launch_handle.dart';
import 'data/instance_providers.dart';
import 'data/instance_store.dart';
import 'data/launch_factory.dart';
import 'data/launch_providers.dart';
import 'data/prefs_settings_store.dart';
import 'data/settings.dart';

import 'ui/download/download_screen.dart';
import 'ui/logs/logs_screen.dart';
import 'ui/setup/setup_screen.dart';
import 'ui/instances/instance_detail_screen.dart';
import 'ui/instances/instances_screen.dart';
import 'ui/launch/launch_screen.dart';
import 'ui/shell/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initWindow();

  final store = PrefsSettingsStore();
  // Awaited before the first frame so the app never paints in the wrong language
  // or theme and then flips.
  await store.init();

  final paths = await resolveLauncherPaths();

  runApp(
    OhMyMcApp(
      store: store,
      paths: paths,
      instanceStore: FileInstanceStore(root: paths.data),
    ),
  );
}

/// Window setup, before the first frame.
///
/// A no-op off the desktop, and it deliberately does **not** hide the native
/// decorations. On Wayland there is no portable way to drag a frameless window
/// (the protocol needs an input serial that a synthetic drag call cannot
/// supply), so the compositor's own decoration is what makes dragging, snapping
/// and double-click-maximise work natively. `window_manager` is used here only
/// for sizing, which is the one thing Flutter cannot do for a desktop window.
Future<void> _initWindow() async {
  if (!_isDesktop) return;
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    // Below roughly this width the rail plus a three-column instance grid stops
    // fitting, so the limit is a layout fact rather than a preference.
    minimumSize: Size(940, 620),
    size: Size(1200, 780),
    center: true,
    title: 'oh my mc',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

bool get _isDesktop =>
    !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

/// The launcher's data and game roots.
///
/// Both live under the app-support directory: an uninstall can then be explained
/// as "delete one folder", and the launcher never writes into a user's existing
/// `.minecraft` without being asked.
Future<LauncherPaths> resolveLauncherPaths() async {
  final support = await getApplicationSupportDirectory();
  final data = Directory(p.join(support.path, 'oh_my_mc'));
  final game = Directory(p.join(data.path, 'minecraft'));
  await data.create(recursive: true);
  await game.create(recursive: true);
  return LauncherPaths(data: data, game: game);
}

/// The app entry widget.
///
/// Every dependency is a parameter so a test can mount the real widget tree with
/// a memory settings store, a temporary directory and a fake [LaunchHandle].
class OhMyMcApp extends StatelessWidget {
  const OhMyMcApp({
    super.key,
    this.store,
    this.instanceStore,
    this.paths,
    this.launchHandleFactory,
    this.locale,
    this.themeMode,
    this.initialLocation = Routes.instances,
  });

  final SettingsStore? store;
  final InstanceStore? instanceStore;

  /// Where the launcher reads and writes. `null` in tests that do not launch.
  final LauncherPaths? paths;

  /// Replaces the real process-backed handle.
  final LaunchHandleFactory? launchHandleFactory;

  final Locale? locale;
  final m3.ThemeMode? themeMode;
  final String initialLocation;

  @override
  Widget build(BuildContext context) {
    final settingsStore = store ?? _seededFromArguments();
    final pathResolver = paths;
    final factory = launchHandleFactory;

    return ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWith((ref) => settingsStore),
        instanceStoreProvider.overrideWith(
          (ref) => instanceStore ?? MemoryInstanceStore(),
        ),
        if (pathResolver != null)
          launcherPathsProvider.overrideWith((ref) => pathResolver),
        launchHandleFactoryProvider.overrideWith(
          // A real factory needs real paths; without them, a test that forgot to
          // inject one gets a clear error rather than a JVM.
          (ref) =>
              factory ??
              (pathResolver == null
                  ? _noLauncher
                  : realLaunchHandleFactory(ref)),
        ),
      ],
      child: AppRoot(
        initialLocation: initialLocation,
        screens: (context, state) => _screenFor(context, state),
      ),
    );
  }

  /// The route table, in one place.
  ///
  /// The shell wraps every screen rather than living in the router: a route's
  /// widget is the page *content*, and rebuilding the pane on every navigation
  /// would restart its selection animation.
  Widget _screenFor(BuildContext context, GoRouterState state) {
    // `state.uri.path` is the *concrete* path (`/instances/survival`), so it can
    // never equal the pattern `Routes.instanceDetailPattern` (`/instances/:id`).
    // Comparing them left the detail route falling through to the launch screen,
    // which is exactly what "Open settings does nothing" looked like. The route
    // parameter is the thing that says which screen this is.
    final detailId = state.pathParameters['id'];
    final child = switch (state.uri.path) {
      Routes.instances => const InstancesScreen(),
      Routes.download => const DownloadScreen(),
      Routes.setup => const SetupScreen(),
      Routes.logs => const LogsScreen(),
      _ when detailId != null => InstanceDetailScreen(id: detailId),
      _ => const LaunchScreen(),
    };
    return AppShell(location: state.uri.path, child: child);
  }

  /// Production replaces this override with [realLaunchHandleFactory]; a test
  /// that forgets to pass either gets a clear error instead of a JVM.
  static LaunchHandle _noLauncher(Instance instance) => throw StateError(
    'OhMyMcApp needs `paths` or `launchHandleFactory` to launch',
  );

  /// Builds an in-memory store from [locale]/[themeMode], so tests that mount
  /// `OhMyMcApp(locale: ...)` need no platform plugin.
  MemorySettingsStore _seededFromArguments() {
    return MemorySettingsStore(
      AppSettings(
        theme: switch (themeMode) {
          m3.ThemeMode.light => ThemePreference.light,
          m3.ThemeMode.dark => ThemePreference.dark,
          _ => ThemePreference.system,
        },
        language: switch (locale?.languageCode) {
          'zh' => LanguagePreference.chinese,
          'en' => LanguagePreference.english,
          _ => LanguagePreference.system,
        },
      ),
    );
  }
}
