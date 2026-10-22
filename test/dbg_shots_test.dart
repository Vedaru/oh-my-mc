@Tags(['shots'])
library;

import 'dart:io';

import 'package:material_ui/material_ui.dart' as m3;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' as w;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/core/mc/game_folders.dart';
import 'package:oh_my_mc/core/mods/mod_scanner.dart';
import 'package:oh_my_mc/data/install_providers.dart';
import 'package:oh_my_mc/core/install/version_installer.dart';
import 'package:oh_my_mc/core/net/progress.dart';
import 'package:oh_my_mc/data/launch_providers.dart';
import 'package:oh_my_mc/core/launch/launch_handle.dart';
import 'package:oh_my_mc/data/instance_providers.dart';
import 'package:oh_my_mc/data/mods_providers.dart';
import 'package:oh_my_mc/data/instance_store.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:oh_my_mc/main.dart';
import 'package:path/path.dart' as p;

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

Instance _instance(String id, String name, String version, {DateTime? last}) =>
    Instance(
      id: id,
      name: name,
      versionId: version,
      createdAt: DateTime(2026, 1, 1),
      lastPlayedAt: last,
      totalPlaytime: const Duration(hours: 12, minutes: 30),
    );

void main() {
  setUpAll(_loadFonts);

  Future<void> shoot(
    WidgetTester tester,
    String route,
    String file, {
    List<Instance> instances = const [],
    AppSettings settings = AppSettings.defaults,
    double scrollDown = 0,
    List<Override> overrides = const [],
    String? openKey,
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
      await tester.pumpAndSettle();
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

  // A fixed answer for the content-folder scan: the shot exists to review the
  // arrangement of the section, not to race the filesystem.
  Override foldersOverride({
    int mods = 0,
    int resourcePacks = 0,
    int shaderPacks = 0,
    int saves = 0,
  }) => gameFolderScannerProvider.overrideWithValue(
    (root) async => [
      GameFolder(kind: GameFolderKind.mods, path: '$root/mods', entries: mods),
      GameFolder(
        kind: GameFolderKind.resourcePacks,
        path: '$root/resourcepacks',
        entries: resourcePacks,
      ),
      GameFolder(
        kind: GameFolderKind.shaderPacks,
        path: '$root/shaderpacks',
        entries: shaderPacks,
      ),
      GameFolder(
        kind: GameFolderKind.saves,
        path: '$root/saves',
        entries: saves,
      ),
    ],
  );

  testWidgets('detail', (tester) async {
    await shoot(
      tester,
      '/instances/a',
      'detail',
      instances: [_instance('a', 'Survival', '1.20.1')],
    );
  });

  testWidgets('detail files', (tester) async {
    await shoot(
      tester,
      '/instances/a',
      'detail-files',
      instances: [_instance('a', 'Survival', '1.20.1')],
      scrollDown: 900,
      overrides: [
        foldersOverride(mods: 14, resourcePacks: 3, shaderPacks: 0, saves: 6),
      ],
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

  testWidgets('download', (tester) async {
    await shoot(tester, '/download', 'download');
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
