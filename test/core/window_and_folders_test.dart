import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/core/mc/game_folders.dart';
import 'package:oh_my_mc/core/mc/version_json.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/data/settings.dart';

Instance _instance({
  int? width,
  int? height,
  bool fullscreen = false,
  List<String> gameArgs = const [],
}) => Instance(
  id: 'i',
  name: 'I',
  versionId: '1.20.1',
  createdAt: DateTime(2026, 1, 1),
  windowWidth: width,
  windowHeight: height,
  fullscreen: fullscreen,
  gameArgs: gameArgs,
);

VersionJson _version() => VersionJson.fromJson(
  jsonDecode('''
{
  "id": "1.20.1",
  "type": "release",
  "mainClass": "net.minecraft.client.main.Main",
  "assetIndex": {"id": "5", "sha1": "", "size": 0, "totalSize": 0, "url": "https://example.invalid/i.json"},
  "assets": "5",
  "libraries": [],
  "downloads": {"client": {"sha1": "", "size": 0, "url": "https://example.invalid/c.jar"}}
}
''') as Map<String, dynamic>,
);

void main() {
  group('window size', () {
    test('round-trips through the instance file', () {
      final instance = _instance(width: 1280, height: 720, fullscreen: true);
      final parsed = Instance.fromJson(instance.toJson());

      expect(parsed.windowWidth, 1280);
      expect(parsed.windowHeight, 720);
      expect(parsed.fullscreen, isTrue);
      expect(parsed, instance);
    });

    test('a default window is absent from the file, not zeroed', () {
      final json = _instance().toJson();
      expect(json.containsKey('windowWidth'), isFalse);
      expect(json.containsKey('fullscreen'), isFalse);

      // A corrupt value degrades to "the game decides", never to a 0-pixel window.
      expect(
        Instance.fromJson({...json, 'windowWidth': 0}).windowWidth,
        isNull,
      );
      expect(
        Instance.fromJson({...json, 'windowHeight': -5}).windowHeight,
        isNull,
      );
    });

    test('clearWindowSize resets both dimensions', () {
      final sized = _instance(width: 800, height: 600);
      final cleared = sized.copyWith(clearWindowSize: true);

      expect(cleared.windowWidth, isNull);
      expect(cleared.windowHeight, isNull);
    });

    test('the launch request carries --width/--height/--fullscreen', () {
      final request = buildLaunchRequest(
        instance: _instance(
          width: 1280,
          height: 720,
          fullscreen: true,
          gameArgs: const ['--demo'],
        ),
        settings: AppSettings.defaults,
        version: _version(),
      );

      expect(request.extraGameArgs, [
        '--demo',
        '--width',
        '1280',
        '--height',
        '720',
        '--fullscreen',
      ]);
    });

    test('no window args when nothing is set', () {
      final request = buildLaunchRequest(
        instance: _instance(),
        settings: AppSettings.defaults,
        version: _version(),
      );

      expect(request.extraGameArgs, isEmpty);
    });

    test('half a size sends neither dimension', () {
      // Both fields are required by the game; one of them is a typo, and the UI
      // never stores a half pair either.
      final request = buildLaunchRequest(
        instance: _instance(width: 1280),
        settings: AppSettings.defaults,
        version: _version(),
      );

      expect(request.extraGameArgs, isEmpty);
    });
  });

  group('content folders', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('game-folders');
    });

    tearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });

    test('counts what the game would load, not every file', () async {
      File('${root.path}/mods/sodium.jar').createSync(recursive: true);
      File('${root.path}/mods/lithium.jar.disabled')
          .createSync(recursive: true);
      File('${root.path}/mods/readme.txt').createSync(recursive: true);
      Directory('${root.path}/resourcepacks/faithful')
          .createSync(recursive: true);
      File('${root.path}/resourcepacks/vanilla-tweaks.zip')
          .createSync(recursive: true);
      File('${root.path}/shaderpacks/bsl.zip').createSync(recursive: true);
      Directory('${root.path}/saves/World1').createSync(recursive: true);
      File('${root.path}/saves/World1/level.dat').createSync(recursive: true);

      final folders = await scanGameFolders(root.path);
      final byKind = {for (final f in folders) f.kind: f};

      // A disabled mod is still a mod the user put there.
      expect(byKind[GameFolderKind.mods]!.entries, 2);
      // Zip or directory; a stray text file is not a pack.
      expect(byKind[GameFolderKind.resourcePacks]!.entries, 2);
      expect(byKind[GameFolderKind.shaderPacks]!.entries, 1);
      // Only directories: `level.dat` inside a save is not a save.
      expect(byKind[GameFolderKind.saves]!.entries, 1);
    });

    test('a missing folder is zero, not an error', () async {
      final folders = await scanGameFolders(root.path);

      expect(folders, hasLength(GameFolderKind.values.length));
      expect(folders.every((f) => f.entries == 0), isTrue);
      expect(
        folders.first.path,
        '${root.path}/${GameFolderKind.mods.directoryName}',
      );
    });
  });
}
