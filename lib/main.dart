import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
import 'l10n/l10n.dart';
import 'ui/download/download_screen.dart';
import 'ui/instances/instances_screen.dart';
import 'ui/launch/launch_screen.dart';
import 'ui/shell/app_shell.dart';
import 'ui/shell/shell_icons.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
    this.initialLocation = Routes.launch,
  });

  final SettingsStore? store;
  final InstanceStore? instanceStore;

  /// Where the launcher reads and writes. `null` in tests that do not launch.
  final LauncherPaths? paths;

  /// Replaces the real process-backed handle.
  final LaunchHandleFactory? launchHandleFactory;

  final Locale? locale;
  final ThemeMode? themeMode;
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
    final child = switch (state.uri.path) {
      Routes.instances ||
      Routes.instanceDetailPattern => const InstancesScreen(),
      Routes.download => const DownloadScreen(),
      Routes.setup ||
      Routes.logs => _Pending(icon: ShellIcons.forRoute(state.uri.path)),
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
          ThemeMode.light => ThemePreference.light,
          ThemeMode.dark => ThemePreference.dark,
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

/// A screen with no implementation yet. Named by its icon so a user who reaches
/// it by deep link can tell which screen is missing.
class _Pending extends StatelessWidget {
  const _Pending({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = FluentTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: theme.inactiveColor),
          const SizedBox(height: 8),
          Text(l10n.screenNotReady, style: theme.typography.caption),
        ],
      ),
    );
  }
}
