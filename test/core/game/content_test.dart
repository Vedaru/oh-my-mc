import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/game/content.dart';
import 'package:oh_my_mc/core/game/nbt.dart';
import 'package:oh_my_mc/core/game/options_txt.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory game;

  setUp(() async {
    game = await Directory.systemTemp.createTemp('game-content');
  });
  tearDown(() async {
    if (game.existsSync()) await game.delete(recursive: true);
  });

  File file(String relative, [String content = 'x']) {
    final f = File(p.join(game.path, relative));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
    return f;
  }

  group('options.txt', () {
    test('keeps lines it does not understand, and their order', () {
      final options = OptionsTxt.parse(
        'version:3465\nfov:90\nresourcePacks:["vanilla","file/a.zip"]\nlang:en_us\n',
      );

      options.setResourcePacks(['file/a.zip', 'file/b.zip']);

      final out = options.text;
      expect(out, contains('version:3465'));
      expect(out, contains('fov:90'));
      expect(out, contains('lang:en_us'));
      // Rewritten in place, not appended.
      expect(
        out.indexOf('resourcePacks:'),
        lessThan(out.indexOf('lang:en_us')),
      );
    });

    test('vanilla always comes first and only once', () {
      final options = OptionsTxt.parse('resourcePacks:[]\n');

      options.setResourcePacks(['vanilla', 'file/a.zip', 'vanilla']);

      expect(options.text, contains('resourcePacks:["vanilla","file/a.zip"]'));
      expect(options.resourcePacks, ['vanilla', 'file/a.zip']);
    });

    test('a missing key is inserted, a garbage value reads as vanilla', () {
      final options = OptionsTxt.parse('fov:90\n');
      options.setResourcePacks(['file/a.zip']);
      expect(options.text, contains('resourcePacks:["vanilla","file/a.zip"]'));

      // Hand-edited files exist; one click fixes a pack shown as disabled, an
      // exception on open would not.
      expect(OptionsTxt.parse('resourcePacks:garbage').resourcePacks, [
        'vanilla',
      ]);
    });

    test('a pack name with a quote survives the round trip', () {
      final options = OptionsTxt.parse('');
      options.setResourcePacks(['file/a "quoted" pack.zip']);

      expect(options.resourcePacks, ['vanilla', 'file/a "quoted" pack.zip']);
    });
  });

  group('nbt', () {
    test('round-trips a server list', () {
      final root = NbtCompound({
        'servers': NbtList(NbtTagId.compound, [
          NbtCompound({
            'name': NbtString('Survival'),
            'ip': NbtString('192.168.1.9:25565'),
            'icon': NbtString(''),
            'acceptTextures': NbtByte(1),
          }),
        ]),
      });

      final decoded = readNbt(writeNbt(root));
      final servers = decoded.values['servers']! as NbtList;

      expect(servers.items, hasLength(1));
      final server = servers.items.single as NbtCompound;
      expect(server.string('name'), 'Survival');
      expect(server.string('ip'), '192.168.1.9:25565');
    });

    test('truncated data is an error, not a crash', () {
      expect(
        () => readNbt(writeNbt(NbtCompound()).sublist(0, 3)),
        throwsA(isA<NbtException>()),
      );
    });
  });

  group('lists', () {
    test('resource packs report their state from options.txt', () async {
      file('resourcepacks/enabled.zip');
      Directory(p.join(game.path, 'resourcepacks/folder pack')).createSync();
      file('resourcepacks/disabled.zip');
      file('resourcepacks/readme.txt');
      file('options.txt', 'resourcePacks:["vanilla","file/enabled.zip"]\n');

      final packs = await GameContent(game.path)
          .list(ContentKind.resourcePacks);

      // The readme is not a pack.
      expect(packs.map((e) => e.name), [
        'disabled.zip',
        'enabled.zip',
        'folder pack',
      ]);
      expect(packs.firstWhere((e) => e.name == 'enabled.zip').enabled, isTrue);
      expect(
        packs.firstWhere((e) => e.name == 'disabled.zip').enabled,
        isFalse,
      );
    });

    test('toggling a pack rewrites options.txt and nothing else', () async {
      file('resourcepacks/a.zip');
      final options = file(
        'options.txt',
        'fov:90\nresourcePacks:["vanilla"]\n',
      );

      await GameContent(game.path).setResourcePackEnabled('a.zip', true);

      final text = options.readAsStringSync();
      expect(text, contains('fov:90'));
      expect(text, contains('"file/a.zip"'));
      // Now off again.
      await GameContent(game.path).setResourcePackEnabled('a.zip', false);
      expect(options.readAsStringSync(), isNot(contains('file/a.zip')));
    });

    test('saves are listed newest first with a size', () async {
      Directory(p.join(game.path, 'saves/Old World'))
          .createSync(recursive: true);
      file('saves/Old World/level.dat', 'x' * 100);
      Directory(p.join(game.path, 'saves/New World'))
          .createSync(recursive: true);
      file('saves/New World/level.dat', 'y' * 10);
      // The folders were created in order, so their mtimes are in order too - which
      // is what the list sorts on (a world's last-played time is its directory's
      // mtime, since the game touches the folder when it saves).
      final saves = await GameContent(game.path).list(ContentKind.saves);

      expect(saves.map((e) => e.name), ['New World', 'Old World']);
      expect(saves.first.sizeBytes, greaterThan(0));
    });

    test(
      'servers come from servers.dat, and deleting one keeps the rest',
      () async {
        final content = GameContent(game.path);
        await content.addServer(name: 'Survival', ip: '192.168.1.9:25565');
        await content.addServer(name: 'Creative', ip: 'example.invalid:25565');

        var servers = await content.list(ContentKind.servers);
        expect(servers.map((e) => e.name), ['Survival', 'Creative']);

        await content.delete(ContentKind.servers, '192.168.1.9:25565');

        servers = await content.list(ContentKind.servers);
        expect(servers.map((e) => e.name), ['Creative']);
      },
    );

    test('a corrupt servers.dat reads as empty rather than throwing', () async {
      file('servers.dat', 'not nbt at all');

      expect(await GameContent(game.path).list(ContentKind.servers), isEmpty);
    });

    test('deleting a world removes its directory', () async {
      Directory(p.join(game.path, 'saves/Gone')).createSync(recursive: true);
      file('saves/Gone/level.dat');

      await GameContent(game.path)
          .delete(ContentKind.saves, p.join(game.path, 'saves/Gone'));

      expect(Directory(p.join(game.path, 'saves/Gone')).existsSync(), isFalse);
    });

    test('a folder with no content is an empty list, not an error', () async {
      expect(
        await GameContent(game.path).list(ContentKind.shaderPacks),
        isEmpty,
      );
      expect(await GameContent(game.path).list(ContentKind.saves), isEmpty);
    });
  });
}
