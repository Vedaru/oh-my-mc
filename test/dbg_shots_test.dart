@Tags(['shots'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart' as m3;
import 'package:flutter/services.dart';
import 'package:flutter/painting.dart' show decodeImageFromList;
import 'package:flutter/widgets.dart' as w;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_mc/ui/theme/app_theme.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/core/mods/mod_scanner.dart';
import 'package:oh_my_mc/core/mods/update_checker.dart';
import 'package:oh_my_mc/core/net/cancellation.dart';
import 'package:oh_my_mc/core/net/version_manifest.dart';
import 'package:oh_my_mc/core/account/account.dart';
import 'package:oh_my_mc/data/account_providers.dart';
import 'package:oh_my_mc/data/account_store.dart';
import 'package:oh_my_mc/data/install_providers.dart';
import 'package:oh_my_mc/data/modpack_providers.dart';
import 'package:oh_my_mc/data/skin_providers.dart';
import 'package:oh_my_mc/data/wallpaper_provider.dart';
import 'package:oh_my_mc/core/install/version_installer.dart';
import 'package:oh_my_mc/core/net/progress.dart';
import 'package:oh_my_mc/core/logs/log_files.dart';
import 'package:oh_my_mc/data/log_providers.dart';
import 'package:oh_my_mc/core/mods/modrinth.dart';
import 'package:oh_my_mc/data/modrinth_providers.dart';
import 'package:oh_my_mc/core/diagnostics/lan_discovery.dart';
import 'package:oh_my_mc/core/diagnostics/network_info.dart';
import 'package:oh_my_mc/data/diagnostics_providers.dart';
import 'package:oh_my_mc/core/game/content.dart';
import 'package:oh_my_mc/core/server/server_ping.dart';
import 'package:oh_my_mc/data/server_providers.dart';
import 'package:oh_my_mc/data/game_content_provider.dart';
import 'package:oh_my_mc/core/update/update_check.dart';
import 'package:oh_my_mc/ui/setup/about_panel.dart';
import 'package:oh_my_mc/data/launch_providers.dart';
import 'package:oh_my_mc/core/launch/launch_handle.dart';
import 'package:oh_my_mc/data/instance_providers.dart';
import 'package:oh_my_mc/data/mods_providers.dart';
import 'package:oh_my_mc/data/instance_store.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:oh_my_mc/main.dart';
import 'package:path/path.dart' as p;
import 'package:oh_my_mc/l10n/generated/app_localizations.dart';

/// Loads a font so the shots contain glyphs instead of boxes.
///
/// Best-effort on purpose: a headless box may ship no fonts at all, and that must
/// not fail the harness (only make it less readable). `SHOT_FONT=<path>` wins,
/// then any TTF/OTF under the usual font directories. A CJK face is needed for
/// the zh shots; without one those render as tofu and the layout is still valid.
Future<void> _loadFonts() async {
  final font = _findFont();
  if (font == null) {
    // ignore: avoid_print
    print(
      'shots: no font found (set SHOT_FONT=<path>); text will render as boxes',
    );
    return;
  }
  final bytes = File(font).readAsBytesSync();
  for (final family in ['Roboto', 'Segoe UI']) {
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }

  // The console faces (`AppTheme.mono`) are separate families: without one loaded,
  // every log line and path in the shots renders as boxes, which is how the install
  // log tail looked before this. `SHOT_MONO=<path>` wins, then a bundled face.
  final mono = _findMono();
  if (mono != null) {
    final monoBytes = File(mono).readAsBytesSync();
    for (final family in ['JetBrains Mono', 'Consolas', 'DejaVu Sans Mono']) {
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(monoBytes)));
      await loader.load();
    }
  }

  // Material's own glyph font ships with the SDK, not with this package, and a
  // test binding loads neither: without it every `Icons.*` in the shots is a
  // square, which reads as "the icons are broken" when they are not.
  final icons = _findIconFont();
  if (icons == null) {
    // ignore: avoid_print
    print('shots: MaterialIcons font not found; icons will render as boxes');
    return;
  }
  final iconLoader = FontLoader(
    'MaterialIcons',
  )..addFont(Future.value(ByteData.sublistView(File(icons).readAsBytesSync())));
  await iconLoader.load();
}

/// The SDK's glyph font, found by walking up from the test runner's own binary
/// (`<flutter>/bin/cache/dart-sdk/bin/dart` -> `<flutter>/bin/cache/artifacts/…`).
String? _findIconFont() {
  final fromEnv = Platform.environment['SHOT_ICON_FONT'];
  if (fromEnv != null && File(fromEnv).existsSync()) return fromEnv;
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    final candidate = File(
      p.join(
        dir.path,
        'cache',
        'artifacts',
        'material_fonts',
        'MaterialIcons-Regular.otf',
      ),
    );
    if (candidate.existsSync()) return candidate.path;
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  return null;
}

/// A monospace face for the console text, or `null`.
String? _findMono() {
  final fromEnv = Platform.environment['SHOT_MONO'];
  if (fromEnv != null && File(fromEnv).existsSync()) return fromEnv;
  for (final candidate in const [
    '/workspace/fonts/JetBrainsMono-Regular.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
  ]) {
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

String? _findFont() {
  final fromEnv = Platform.environment['SHOT_FONT'];
  if (fromEnv != null && File(fromEnv).existsSync()) return fromEnv;
  for (final dir in ['/usr/share/fonts', '/usr/local/share/fonts']) {
    final root = Directory(dir);
    if (!root.existsSync()) continue;
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File) continue;
      final path = entity.path.toLowerCase();
      if (path.endsWith('.ttf') || path.endsWith('.otf')) return entity.path;
    }
  }
  return null;
}

Instance _instance(
  String id,
  String name,
  String version, {
  DateTime? last,
  LoaderKind loader = LoaderKind.vanilla,
}) => Instance(
  id: id,
  name: name,
  versionId: version,
  loader: loader,
  loaderVersion: loader.isModded ? '0.16.9' : null,
  createdAt: DateTime(2026, 1, 1),
  lastPlayedAt: last,
  totalPlaytime: const Duration(hours: 12, minutes: 30),
);

void main() {
  setUpAll(_loadFonts);

  /// Captures one widget on its own, for a panel whose interesting state needs an
  /// interaction the route-based `shoot` cannot reach (a section below the fold).
  Future<void> shootWidget(
    WidgetTester tester,
    w.Widget child,
    String file, {
    List<Override> overrides = const [],
    String? tapKey,
  }) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.platformBrightnessTestValue = w.Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: m3.MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.material(w.Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: m3.Scaffold(
            body: m3.Padding(
              padding: const m3.EdgeInsets.all(24),
              child: child,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    if (tapKey != null) {
      await tester.tap(find.byKey(w.ValueKey(tapKey)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
    await expectLater(
      find.byType(m3.MaterialApp),
      matchesGoldenFile('shots/$file.png'),
    );
  }

  Future<void> shoot(
    WidgetTester tester,
    String route,
    String file, {
    List<Instance> instances = const [],
    AppSettings settings = AppSettings.defaults,
    double scrollDown = 0,
    List<Override> overrides = const [],
    String? openKey,
    String? tapAfter,
    String? tapText,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // `AppSettings.defaults` follows the system, and the test binding says "light"
    // unless told otherwise - so a shot could come out light or dark depending on
    // which test ran before it. The launcher is used dark; pin it.
    tester.platformDispatcher.platformBrightnessTestValue = w.Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    final data = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('shot'),
    ))!;
    addTearDown(() async {
      if (await data.exists()) await data.delete(recursive: true);
    });

    await tester.pumpWidget(
      OhMyMcApp(
        store: MemorySettingsStore(settings),
        instanceStore: MemoryInstanceStore(instances),
        paths: LauncherPaths(
          data: data,
          game: Directory(p.join(data.path, 'minecraft')),
        ),
        initialLocation: route,
        overrides: overrides,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    if (openKey != null) {
      // A dialog is part of the screen it belongs to: capture it open rather than
      // only photographing the resting page.
      await tester.tap(find.byKey(w.ValueKey(openKey)));
      // Bounded pumps, not `pumpAndSettle`: a dialog with an autofocused field
      // has a blinking cursor, which is an animation that never settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // A section whose rows read something asynchronous (a server's ping) needs one
      // more frame after the answer lands, or the shot captures the pending state.
      await tester.pump(const Duration(milliseconds: 400));
    }

    if (tapText != null) {
      // A control with no key of its own - a segmented button's segment - is still
      // reachable by its label.
      await tester.tap(find.text(tapText).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    if (tapAfter != null) {
      // A shot of a state that needs one more interaction - checking for updates -
      // with the answer already faked, so the capture is deterministic.
      await tester.tap(find.byKey(w.ValueKey(tapAfter)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    if (scrollDown > 0) {
      // A page taller than the window: the lower sections only exist once the
      // scroll view has built them.
      await tester.drag(
        find.byType(w.Scrollable).first,
        Offset(0, -scrollDown),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    await expectLater(
      find.byType(m3.MaterialApp),
      matchesGoldenFile('shots/$file.png'),
    );
  }

  testWidgets('launch', (tester) async {
    await shoot(
      tester,
      '/launch',
      'launch',
      instances: [
        _instance(
          'survival',
          'Survival',
          '1.20.1',
          last: DateTime(2026, 10, 20),
        ),
      ],
    );
  });

  testWidgets('instances', (tester) async {
    await shoot(
      tester,
      '/instances',
      'instances',
      instances: [
        _instance('a', 'Survival', '1.20.1', last: DateTime(2026, 10, 20)),
        _instance('b', 'Creative', '26.3'),
        _instance('c', 'Modded', '1.19.2'),
      ],
    );
  });

  testWidgets('instances empty', (tester) async {
    await shoot(tester, '/instances', 'instances-empty');
  });

  // A fixed mods folder for the screenshot: the shot reviews the arrangement, and
  // a real scan would need jars on disk.

  testWidgets('detail settings', (tester) async {
    await shoot(
      tester,
      '/instances/a',
      'detail-settings',
      instances: [_instance('a', 'Survival', '1.20.1')],
      openKey: 'detail-section-settings',
    );
  });

  // The content kinds are separate pages now, so the review shot is one of them: the
  // resource packs, with the section list beside them.
  testWidgets('detail resource packs', (tester) async {
    await shoot(
      tester,
      '/instances/a',
      'detail-resource-packs',
      instances: [_instance('a', 'Survival', '1.20.1')],
      openKey: 'detail-section-resource-packs',
      overrides: [
        gameContentProvider.overrideWith(
          (ref) =>
              (root) => _ShotContent(),
        ),
      ],
    );
  });

  // The same pack page *after* a check: the update action has to fit in a row that
  // already carries a switch and a delete, and the header grows a second button.
  testWidgets('instance pack updates', (tester) async {
    await shoot(
      tester,
      '/instances/a',
      'instance-pack-updates',
      instances: [_instance('a', 'Survival', '1.20.1')],
      openKey: 'detail-section-resource-packs',
      overrides: [
        gameContentProvider.overrideWith(
          (ref) =>
              (root) => _ShotContent(),
        ),
        fileUpdateCheckerProvider.overrideWithValue(
          FileUpdateChecker(_ShotUpdateClient(), hash: (_) async => 'sha1'),
        ),
      ],
      tapAfter: 'content-check-updates',
    );
  });

  testWidgets('instance mods', (tester) async {
    await shoot(
      tester,
      '/instances/a/mods',
      'instance-mods',
      instances: [_instance('a', 'Survival', '1.20.1')],
      overrides: [modsRepositoryProvider.overrideWithValue(_ShotMods())],
    );
  });

  testWidgets('launch running', (tester) async {
    await shoot(
      tester,
      '/launch',
      'launch-running',
      instances: [_instance('a', '26.2', '26.2')],
      overrides: [launchControllerProvider.overrideWith(_ShotRunning.new)],
    );
  });

  testWidgets('launch versions', (tester) async {
    await shoot(
      tester,
      '/launch',
      'launch-versions',
      instances: [
        _instance('a', '26.2', '26.2'),
        _instance('b', 'Modded', '1.20.1'),
        _instance('c', 'Creative', '1.19.2'),
      ],
      openKey: 'launch-version-picker',
    );
  });

  testWidgets('download installing', (tester) async {
    await shoot(
      tester,
      '/download',
      'download-installing',
      overrides: [
        installControllerProvider.overrideWith(_ShotInstall.new),
        installLogProvider.overrideWith(_ShotInstallLog.new),
      ],
    );
  });

  testWidgets('download failed', (tester) async {
    await shoot(
      tester,
      '/download',
      'download-failed',
      overrides: [
        installControllerProvider.overrideWith(_ShotFailedInstall.new),
        installLogProvider.overrideWith(_ShotFailedLog.new),
      ],
    );
  });

  // A wallpaper the review can actually judge: a checked-in gradient fixture, so the
  // shot shows how much of the picture survives the scrim over a real page.
  testWidgets('wallpaper', (tester) async {
    final wallpaper = p.join(
      Directory.current.path,
      'test/fixtures/wallpaper.png',
    );
    // The shell paints a decoded `ui.Image`; decode it here, in real async, so the
    // frame has the picture in it. Without this the shot would "prove" the wallpaper
    // does not work, which is exactly the bug it exists to catch.
    final image = await tester.runAsync(() async {
      final bytes = await File(wallpaper).readAsBytes();
      return decodeImageFromList(bytes);
    });
    await shoot(
      tester,
      '/instances',
      'wallpaper',
      instances: [
        _instance('a', 'Survival', '1.20.1', loader: LoaderKind.fabric),
        _instance('b', 'Creative', '1.21'),
      ],
      settings: AppSettings(backgroundPath: wallpaper),
      overrides: [
        wallpaperImageProvider.overrideWith((ref, path) async => image),
      ],
    );
  });

  // 账户 is a rail destination now, not a settings section: this is the page a user
  // lands on to change who the game starts as.
  testWidgets('accounts page', (tester) async {
    await shoot(
      tester,
      '/accounts',
      'accounts',
      overrides: [
        // A face for the signed-in account: the avatar's job is to make an identity
        // recognisable, and a shot of three fallback icons reviews nothing.
        skinTextureProvider.overrideWith((ref, url) async => _shotSkin()),
        accountStoreProvider.overrideWithValue(
          MemoryAccountStore(
            const AccountList(
              accounts: [
                Account(id: 'offline-Survival', name: 'Survival'),
                Account(id: 'a2', name: 'Alex'),
                Account(
                  id: 'tp',
                  name: 'Builder',
                  kind: AccountKind.thirdParty,
                  server: 'https://auth.example.net/api',
                  uuid: '11111111-2222-3333-4444-555555555555',
                  skinUrl: 'https://textures.example/skin',
                  skinVariant: 'CLASSIC',
                ),
              ],
              activeId: 'offline-Survival',
            ),
          ),
        ),
      ],
    );
  });

  // 联机: the LAN scan and the port mapping, lifted out of 设置 → 网络.
  testWidgets('network page', (tester) async {
    await shoot(
      tester,
      '/network',
      'network',
      overrides: [
        lanInterfacesProvider.overrideWith(
          (ref) async => const [
            LanInterface(name: 'wlan0', ipv4: ['192.168.1.23']),
          ],
        ),
        lanDiscoveryProvider.overrideWith((ref) => _ShotLanWorlds()),
      ],
    );
  });

  testWidgets('download modpacks', (tester) async {
    await shoot(
      tester,
      '/download',
      'download-modpacks',
      instances: [_instance('mc', 'mc', '1.20.1')],
      tapText: 'Modpacks',
      overrides: [
        modpackSearchProvider.overrideWith(
          (ref, query) async => const [
            ModrinthProject(
              id: 'fo',
              slug: 'fabulously-optimized',
              title: 'Fabulously Optimized',
              description:
                  'A performance-focused pack that keeps vanilla behaviour.',
              downloads: 1200000,
            ),
            ModrinthProject(
              id: 'rpo',
              slug: 'raspberry',
              title: 'Raspberry Flavour',
              description: 'A small kitchen-sink pack for 1.20.1.',
              downloads: 43000,
            ),
            ModrinthProject(
              id: 'atm',
              slug: 'all-the-mods',
              title: 'All the Mods 9',
              description: 'The kitchen sink, and the kitchen it came in.',
              downloads: 8700000,
            ),
            ModrinthProject(
              id: 'prom',
              slug: 'prominence',
              title: 'Prominence II RPG',
              description: 'An RPG overhaul with quests and bosses.',
              downloads: 2400000,
            ),
            ModrinthProject(
              id: 'bet',
              slug: 'better-mc',
              title: 'Better MC',
              description: 'Vanilla-plus with a curated mod list.',
              downloads: 3100000,
            ),
            ModrinthProject(
              id: 'van',
              slug: 'vanilla-tweaks',
              title: 'Vanilla Tweaks Pack',
              description: 'Quality of life, nothing that changes the look.',
              downloads: 640000,
            ),
          ],
        ),
      ],
    );
  });

  testWidgets('download content', (tester) async {
    await shoot(
      tester,
      '/download',
      'download-content',
      instances: [_instance('mc', 'mc', '1.20.1')],
      tapText: 'Content',
    );
  });

  testWidgets('download installed versions', (tester) async {
    await shoot(
      tester,
      '/download',
      'download-installed',
      instances: [_instance('mc', 'mc', '1.20.1')],
      overrides: [
        versionListProvider.overrideWith(() => _ShotVersionList()),
        installedVersionsProvider.overrideWith(() => _ShotInstalled()),
      ],
    );
  });

  testWidgets('download', (tester) async {
    // With an instance selected: the content bar's buttons are disabled without one,
    // and the shot exists to review the enabled row.
    await shoot(
      tester,
      '/download',
      'download',
      instances: [_instance('mc', 'mc', '1.20.1')],
      // A real list, not the skeleton: the shot exists to review the page, and the
      // loading state is a frame nobody has an opinion about.
      overrides: [versionListProvider.overrideWith(() => _ShotVersionList())],
    );
  });

  testWidgets('instance mods with updates', (tester) async {
    await shoot(
      tester,
      '/instances/a',
      'instance-mod-updates',
      instances: [
        _instance('a', 'Survival', '1.20.1', loader: LoaderKind.fabric),
      ],
      openKey: 'detail-section-mods',
      overrides: [
        instanceModsProvider.overrideWith(
          (ref, id) async => const [
            ModEntry(
              path: '/shot/mods/sodium-0.5.8.jar',
              enabled: true,
              sizeBytes: 900 * 1024,
              loader: ModLoaderKind.fabric,
              name: 'Sodium',
              version: '0.5.8',
            ),
            ModEntry(
              path: '/shot/mods/iris-1.7.0.jar',
              enabled: true,
              sizeBytes: 3 * 1024 * 1024,
              loader: ModLoaderKind.fabric,
              name: 'Iris Shaders',
              version: '1.7.0',
            ),
          ],
        ),
        modsRepositoryProvider.overrideWithValue(_ShotModsRecorder()),
        fileUpdateCheckerProvider.overrideWithValue(
          FileUpdateChecker(_ShotUpdateClient(), hash: (_) async => 'sha1'),
        ),
      ],
      tapAfter: 'content-check-updates',
    );
  });

  testWidgets('instance servers', (tester) async {
    await shoot(
      tester,
      '/instances/a',
      'instance-servers',
      instances: [_instance('a', 'Survival', '1.20.1')],
      openKey: 'detail-section-servers',
      overrides: [
        gameContentProvider.overrideWith(
          (ref) =>
              (root) => _ShotContent(),
        ),
        serverPingerProvider.overrideWithValue(
          (address) async => switch (address) {
            'play.example.net' => const ServerPing.ok(
              ServerStatus(
                motd: 'A Quiet Place to Build',
                online: 12,
                max: 40,
                latencyMs: 38,
                version: '1.20.1',
              ),
            ),
            'mods.example.net:25566' => const ServerPing.ok(
              ServerStatus(
                motd: 'Create: Above and Beyond',
                online: 4,
                max: 10,
                latencyMs: 91,
                version: '1.19.2',
              ),
            ),
            _ => const ServerPing.failed('timed out'),
          },
        ),
      ],
    );
  });

  testWidgets('instance worlds', (tester) async {
    await shoot(
      tester,
      '/instances/a',
      'instance-worlds',
      instances: [_instance('a', 'Survival', '1.20.1')],
      openKey: 'detail-section-worlds',
      overrides: [
        gameContentProvider.overrideWith(
          (ref) =>
              (root) => _ShotContent(),
        ),
      ],
    );
  });

  testWidgets('content resource packs', (tester) async {
    await shoot(
      tester,
      '/instances/fabric',
      'content-packs',
      instances: const [
        Instance(
          id: 'fabric',
          name: 'Fabulously Optimized',
          versionId: '1.20.1',
          loader: LoaderKind.fabric,
          loaderVersion: '0.16.9',
        ),
      ],
      overrides: [
        gameContentProvider.overrideWith(
          (ref) =>
              (root) => _ShotContent(),
        ),
      ],
    );
  });

  testWidgets('crash diagnosis', (tester) async {
    await shoot(
      tester,
      '/launch',
      'crash',
      instances: const [
        Instance(
          id: 'fabric',
          name: 'Fabulously Optimized',
          versionId: '1.20.1',
          loader: LoaderKind.fabric,
          loaderVersion: '0.16.9',
        ),
      ],
      overrides: [
        instanceListProvider.overrideWith(() => _ShotSelected('fabric')),
        launchControllerProvider.overrideWith(_ShotCrash.new),
      ],
    );
  });

  testWidgets('setup network', (tester) async {
    await shoot(
      tester,
      '/setup',
      'setup-network',
      openKey: 'setup-section-network',
      overrides: [
        lanInterfacesProvider.overrideWith(
          (ref) async => const [
            LanInterface(name: 'docker0', ipv4: ['172.17.0.1']),
            LanInterface(name: 'wlan0', ipv4: ['192.168.1.23']),
          ],
        ),
        // Without a stub the panel shows "…" forever: real interface enumeration never
        // completes inside the shot's fake clock.
        lanDiscoveryProvider.overrideWith((ref) => _ShotLanWorlds()),
      ],
    );
  });

  testWidgets('setup about', (tester) async {
    // The About card *after* a check: the state worth photographing is the upgrade
    // offer, and the section sits below the fold of the settings route.
    await shootWidget(
      tester,
      const AboutPanel(),
      'setup-about',
      overrides: [updateCheckerProvider.overrideWithValue(_ShotUpdater())],
      tapKey: 'about-check',
    );
  });

  testWidgets('mods search', (tester) async {
    await shoot(
      tester,
      '/instances/fabric/mods',
      'mods-search',
      instances: const [
        Instance(
          id: 'fabric',
          name: 'Fabulously Optimized',
          versionId: '1.20.1',
          loader: LoaderKind.fabric,
          loaderVersion: '0.16.9',
        ),
      ],
      overrides: [
        contentSearchProvider.overrideWith(
          (ref, query) async => const [
            ModrinthProject(
              id: 'sodium',
              slug: 'sodium',
              title: 'Sodium',
              description:
                  'Modern rendering engine and the standard for performance',
              downloads: 48000000,
            ),
            ModrinthProject(
              id: 'lithium',
              slug: 'lithium',
              title: 'Lithium',
              description:
                  'No-compromises game logic and performance optimization',
              downloads: 31000000,
            ),
            ModrinthProject(
              id: 'iris',
              slug: 'iris',
              title: 'Iris Shaders',
              description:
                  'A modern shaders mod compatible with OptiFine packs',
              downloads: 27000000,
            ),
          ],
        ),
      ],
      openKey: 'content-install',
    );
  });

  testWidgets('logs sessions', (tester) async {
    await shoot(
      tester,
      '/logs',
      'logs-sessions',
      overrides: [
        launchControllerProvider.overrideWith(_ShotNoSession.new),
        logFilesProvider.overrideWith(
          (ref) async => [
            LogFile(
              file: File('/logs/launch-2026-10-22T23-58-14-26.3.log'),
              label: '26.3 · 23:58',
              modified: DateTime(2026, 10, 22, 23, 58),
              isInstall: false,
            ),
            LogFile(
              file: File('/logs/launch-2026-10-20T18-04-00-1.19.2.log'),
              label: '1.19.2 · 18:04',
              modified: DateTime(2026, 10, 20, 18, 4),
              isInstall: false,
            ),
          ],
        ),
        logTailProvider.overrideWith(
          (ref, path) async => const [
            LogEntry('[23:58:14] [Render thread/INFO]: Setting user: Vedaru'),
            LogEntry(
              '[23:58:14] [Render thread/INFO]: Backend library: LWJGL 3.4.3',
            ),
            LogEntry(
              '[23:58:15] [Download-2/ERROR]: Failed to fetch user properties',
            ),
            LogEntry(
              'com.mojang.authlib.exceptions.InvalidCredentialsException',
              isStderr: true,
            ),
            LogEntry(
              '[23:58:16] [Render thread/INFO]: Reloading ResourceManager',
            ),
          ],
        ),
      ],
    );
  });

  testWidgets('setup', (tester) async {
    await shoot(tester, '/setup', 'setup');
  });

  // The zh shots exist because the two languages have different string lengths:
  // a row that fits in English can clamp or wrap in Chinese, and the screenshots
  // that get reported by hand are usually the Chinese ones.
  testWidgets('setup zh', (tester) async {
    await shoot(
      tester,
      '/setup',
      'setup-zh',
      settings: const AppSettings(
        language: LanguagePreference.chinese,
        theme: ThemePreference.dark,
      ),
    );
  });

  testWidgets('launch zh', (tester) async {
    await shoot(
      tester,
      '/launch',
      'launch-zh',
      settings: const AppSettings(
        language: LanguagePreference.chinese,
        theme: ThemePreference.dark,
      ),
    );
  });

  testWidgets('logs', (tester) async {
    await shoot(tester, '/logs', 'logs');
  });

  testWidgets('app root', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // `AppSettings.defaults` follows the system, and the test binding says "light"
    // unless told otherwise - so a shot could come out light or dark depending on
    // which test ran before it. The launcher is used dark; pin it.
    tester.platformDispatcher.platformBrightnessTestValue = w.Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final data = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('shot2'),
    ))!;
    addTearDown(() async {
      if (await data.exists()) await data.delete(recursive: true);
    });
    await tester.pumpWidget(
      OhMyMcApp(
        store: MemorySettingsStore(AppSettings.defaults),
        instanceStore: MemoryInstanceStore(const []),
        paths: LauncherPaths(
          data: data,
          game: Directory(p.join(data.path, 'minecraft')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
  });
}

class _ShotMods implements ModsRepository {
  @override
  Future<List<ModEntry>> scan(String directory) async => [
    const ModEntry(
      path: '/g/mods/sodium.jar',
      enabled: true,
      sizeBytes: 780000,
      loader: ModLoaderKind.fabric,
      id: 'sodium',
      name: 'Sodium',
      version: '0.5.11',
    ),
    const ModEntry(
      path: '/g/mods/iris.jar',
      enabled: true,
      sizeBytes: 2400000,
      loader: ModLoaderKind.fabric,
      id: 'iris',
      name: 'Iris Shaders',
      version: '1.7.3',
    ),
    const ModEntry(
      path: '/g/mods/jei.jar.disabled',
      enabled: false,
      sizeBytes: 1200000,
      loader: ModLoaderKind.forge,
      id: 'jei',
      name: 'Just Enough Items',
      version: '15.2.0',
    ),
    const ModEntry(
      path: '/g/mods/old.jar',
      enabled: true,
      sizeBytes: 90000,
      loader: ModLoaderKind.unknown,
      problem: 'no mod metadata in the jar',
    ),
  ];

  @override
  Future<String> setEnabled(ModEntry mod, bool enabled) async => mod.path;

  @override
  Future<void> delete(ModEntry mod) async {}
}

/// A download in progress, for the screenshot: the panel is only visible while an
/// install runs, so it cannot be captured from a cold page.
class _ShotInstall extends InstallController {
  @override
  InstallState build() => InstallRunning(
    versionId: '1.20.1',
    progress: const InstallProgress(
      phase: InstallPhase.download,
      step: 6,
      steps: 9,
      detail: '1.20.1',
      download: DownloadProgress(
        filesDone: 12,
        filesTotal: 67,
        bytesDone: 5 * 1024 * 1024,
        bytesTotal: 20 * 1024 * 1024,
        bytesPerSecond: 1024 * 1024,
        currentFile: 'lz4-java-1.10.1.jar',
      ),
    ),
    bytesPerSecond: 1024 * 1024,
  );
}

class _ShotInstallLog extends InstallLogNotifier {
  @override
  List<String> build() => const [
    '21:04:51  install started: 1.20.1',
    '21:04:52  manifest [1/9]',
    '21:04:53  versionJson [2/9] 1.20.1',
    '21:04:55  download [6/9] 12/67 files 5.0/20.0 MB',
  ];
}

class _ShotFailedInstall extends InstallController {
  @override
  InstallState build() => const InstallFailed(
    versionId: '1.20.1',
    message: 'HTTP 503 from piston-data.mojang.com while fetching lz4-java',
  );
}

class _ShotFailedLog extends InstallLogNotifier {
  @override
  List<String> build() => const [
    '21:04:51  install started: 1.20.1',
    '21:04:53  versionJson [2/9] 1.20.1',
    '21:05:02  download [6/9] 12/67 files 5.0/20.0 MB',
    '21:05:31  install failed: HTTP 503 from piston-data.mojang.com',
  ];
}

/// A live session, for the screenshot: stop is the primary action and the version
/// card is locked.
class _ShotRunning extends LaunchController {
  @override
  LaunchSession build() => LaunchSession(
    state: LaunchState.running,
    instanceId: 'a',
    uptime: const Duration(minutes: 3),
    log: const [
      LogLine(
        'launch: java · 132 classpath entries · net.minecraft.client.main.Main',
        LogChannel.launcher,
      ),
      LogLine('[Render thread/INFO]: Setting user: Vedaru', LogChannel.stdout),
      LogLine(
        '[Render thread/INFO]: Backend library: LWJGL version 3.4.1+1',
        LogChannel.stdout,
      ),
      LogLine(
        '[Render thread/INFO]: Using shaderpack: BSL_v8.4',
        LogChannel.stdout,
      ),
      LogLine('[Worker-Main-5/INFO]: Loaded 1283 recipes', LogChannel.stdout),
    ],
  );
}

/// A launch page with no session log, so the screenshots of other pages are not
/// affected by whatever ran last.
class _ShotNoSession extends LaunchController {
  @override
  LaunchSession build() => const LaunchSession.idle();
}

/// A session that ended in the failure the crash card exists for.
class _ShotCrash extends LaunchController {
  @override
  LaunchSession build() => LaunchSession(
    state: LaunchState.exited,
    exitCode: 1,
    instanceId: 'fabric',
    uptime: const Duration(minutes: 6),
    log: const [
      LogLine(
        '[12:00:00] [main/INFO]: Loading 214 mods from /mods',
        LogChannel.stdout,
      ),
      LogLine(
        '[12:00:04] [Render thread/INFO]: Backend library: LWJGL 3.4.3',
        LogChannel.stdout,
      ),
      LogLine(
        '[12:31:12] [Render thread/ERROR]: java.lang.OutOfMemoryError: Java heap space',
        LogChannel.stderr,
      ),
      LogLine(
        '\tat net.minecraft.client.renderer.chunk.RenderChunk.rebuild(RenderChunk.java:184)',
        LogChannel.stderr,
      ),
    ],
  );
}

/// An instance list with one selected instance, for pages that need the selection
/// to be non-empty without a round trip through the launch flow.
class _ShotSelected extends InstanceListNotifier {
  _ShotSelected(this.id);

  final String id;

  @override
  InstanceListState build() => InstanceListReady(const [
    Instance(
      id: 'fabric',
      name: 'Fabulously Optimized',
      versionId: '1.20.1',
      loader: LoaderKind.fabric,
      loaderVersion: '0.16.9',
    ),
  ], selectedId: id);
}

/// A content layer with a plausible list, so the shot does not depend on a real
/// game directory existing in the test's temp folder.
class _ShotContent extends GameContent {
  _ShotContent() : super('/shot');

  @override
  Future<List<ContentEntry>> list(ContentKind kind) async => switch (kind) {
    ContentKind.resourcePacks => const [
      ContentEntry(
        name: 'Faithful 32x.zip',
        path: '/shot/resourcepacks/Faithful 32x.zip',
        isDirectory: false,
        sizeBytes: 18 * 1024 * 1024,
        enabled: true,
      ),
      ContentEntry(
        name: 'Fresh Animations.zip',
        path: '/shot/resourcepacks/Fresh Animations.zip',
        isDirectory: false,
        sizeBytes: 6 * 1024 * 1024,
        enabled: true,
      ),
      ContentEntry(
        name: 'Stay True.zip',
        path: '/shot/resourcepacks/Stay True.zip',
        isDirectory: false,
        sizeBytes: 3 * 1024 * 1024,
        enabled: false,
      ),
    ],
    ContentKind.saves => const [
      ContentEntry(
        name: 'Survival',
        path: '/shot/saves/Survival',
        isDirectory: true,
        sizeBytes: 214 * 1024 * 1024,
        detail: 'played 2 h ago',
      ),
      ContentEntry(
        name: 'Creative Test',
        path: '/shot/saves/Creative Test',
        isDirectory: true,
        sizeBytes: 48 * 1024 * 1024,
        detail: 'played 6 d ago',
      ),
    ],
    ContentKind.servers => const [
      ContentEntry(name: 'SMP', path: 'play.example.net', isDirectory: false),
      ContentEntry(
        name: 'Modded',
        path: 'mods.example.net:25566',
        isDirectory: false,
      ),
      ContentEntry(name: 'LAN', path: '192.168.1.20:25565', isDirectory: false),
    ],
    _ => const [],
  };
}

/// A release feed with a newer version, so the about shot shows the upgrade card
/// instead of the empty state.
class _ShotUpdater extends UpdateChecker {
  @override
  Future<UpdateCheck?> check({required String currentVersion}) async =>
      const UpdateCheck(
        isNewer: true,
        latest: ReleaseInfo(
          version: '0.2.0',
          title: '0.2.0',
          notes:
              '- 资源包 / 光影 / 数据包 直接从下载页安装\n'
              '- 崩溃时给出一句话原因和对应的按钮\n'
              '- 测速后自动选择下载源',
          pageUrl: 'https://example.invalid/releases/v0.2.0',
          installerUrl: 'https://example.invalid/setup.exe',
        ),
      );

  @override
  void close() {}
}

/// Two worlds announced on the LAN, so the 联机 section has content in the shot.
class _ShotLanWorlds extends LanDiscovery {
  @override
  Future<List<LanWorld>> discover({
    Future<List<LanWorld>> Function(Duration window)? listener,
  }) async => const [
    LanWorld(motd: "Vedaru's Survival", port: 54321, address: '192.168.1.9'),
    LanWorld(motd: 'Creative Test', port: 25566, address: '192.168.1.14'),
  ];
}

/// Records the delete an update performs, without touching the disk.
class _ShotModsRecorder implements ModsRepository {
  @override
  Future<List<ModEntry>> scan(String directory) async => const [];

  @override
  Future<String> setEnabled(ModEntry mod, bool enabled) async => mod.path;

  @override
  Future<void> delete(ModEntry mod) async {}
}

/// Two of the four shot mods have a newer version, which is what the shot shows.
class _ShotUpdateClient implements ModrinthClient {
  @override
  Future<ModrinthVersion> versionForFile(
    String sha1, {
    CancelToken? cancel,
  }) async => const ModrinthVersion(
    id: 'installed',
    projectId: 'p1',
    name: 'Installed',
    versionNumber: '0.5.8',
    files: [],
    dependencies: [],
  );

  @override
  Future<ModrinthVersion> versionFor(
    String projectId, {
    required String gameVersion,
    String? loader,
    String projectType = 'mod',
    CancelToken? cancel,
  }) async => const ModrinthVersion(
    id: 'latest',
    projectId: 'p1',
    name: 'Latest',
    versionNumber: '0.6.0',
    files: [],
    dependencies: [],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A fixed version list: the shot exists to review the row anatomy (status, type,
/// installed marker, uninstall action), not to race a manifest download.
class _ShotVersionList extends VersionListController {
  @override
  VersionListState build() => VersionListReady(
    VersionManifest.fromJson({
      'latest': {'release': '1.21', 'snapshot': '24w14a'},
      'versions': [
        // Real dates, spread out: a column where every row says the same day is a
        // column that cannot be reviewed.
        for (final row in [
          ('1.21', 'release', '2024-06-13'),
          ('1.20.6', 'release', '2024-04-29'),
          ('1.20.1', 'release', '2023-06-12'),
          ('1.19.4', 'release', '2023-03-14'),
          ('1.19.2', 'release', '2022-08-05'),
          ('1.18.2', 'release', '2022-02-28'),
          ('24w14a', 'snapshot', '2024-04-03'),
        ])
          {
            'id': row.$1,
            'type': row.$2,
            'url': 'https://example.invalid/${row.$1}.json',
            'sha1': 'aa',
            'releaseTime': '${row.$3}T00:00:00+00:00',
          },
      ],
    }),
  );
}

class _ShotInstalled extends InstalledVersions {
  @override
  Set<String> build() => {'1.21', '1.20.1'};
}

/// A 64×64 skin with a face and a hat layer, drawn once for the shots.
///
/// The real texture comes from `textures.minecraft.net`; a screenshot harness must not
/// depend on the network, and a two-colour PNG is enough to review whether a head reads
/// as a head at 28 px.
ui.Image? _skinCache;

ui.Image _shotSkin() {
  final cached = _skinCache;
  if (cached != null) return cached;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 64, 64),
    ui.Paint()..color = const ui.Color(0x00000000),
  );
  // Skin tone, then the two pixels of the eyes at the right offsets of the face block.
  canvas.drawRect(
    const ui.Rect.fromLTWH(8, 8, 8, 8),
    ui.Paint()..color = const ui.Color(0xFFB58863),
  );
  canvas.drawRect(
    const ui.Rect.fromLTWH(10, 11, 1, 1),
    ui.Paint()..color = const ui.Color(0xFF2B2B2B),
  );
  canvas.drawRect(
    const ui.Rect.fromLTWH(13, 11, 1, 1),
    ui.Paint()..color = const ui.Color(0xFF2B2B2B),
  );
  // The hat layer is deliberately transparent: a player not wearing one leaves it empty.
  final image = recorder.endRecording().toImageSync(64, 64);
  _skinCache = image;
  return image;
}
