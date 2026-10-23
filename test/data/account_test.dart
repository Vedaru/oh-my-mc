import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/app/providers.dart';
import 'package:oh_my_mc/core/account/account.dart';
import 'package:oh_my_mc/data/account_providers.dart';
import 'package:oh_my_mc/core/instance/instance.dart';
import 'package:oh_my_mc/core/mc/version_json.dart';
import 'package:oh_my_mc/data/account_store.dart';
import 'package:oh_my_mc/data/launch_factory.dart';
import 'package:oh_my_mc/data/settings.dart';

/// Accounts are a list because a player is not one name - and the identity a launch uses
/// has to be the account that is selected, not the one that happens to be first.
/// The minimum a version needs for a launch request: an id, a main class and no
/// libraries. The argv's identity flags do not depend on more than that.
VersionJson _version() => VersionJson.fromJson({
  'id': '1.20.1',
  'type': 'release',
  'mainClass': 'net.minecraft.client.main.Main',
  'libraries': const [],
  'arguments': const {'game': [], 'jvm': []},
});

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('accounts'));
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  ProviderContainer containerWith(
    AccountStore store, {
    String name = 'Player',
  }) {
    final container = ProviderContainer(
      overrides: [
        launcherPathsProvider.overrideWithValue(
          LauncherPaths(data: tmp, game: Directory('${tmp.path}/game')),
        ),
        accountStoreProvider.overrideWithValue(store),
        settingsStoreProvider.overrideWith(
          (ref) => MemorySettingsStore(AppSettings(playerName: name)),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('the offline uuid is the one the game derives', () {
    // md5("OfflinePlayer:Notch") with the version/variant nibbles patched. Pinned
    // because it is an identity: a wrong digest gives every server a new player.
    expect(
      Account.offlineUuid('Notch'),
      'b50ad385-829d-3141-a216-7e7d7539ba7f',
    );
    expect(Account.offlineUuid('Notch'), Account.offlineUuid('Notch'));
    expect(Account.offlineUuid('Notch'), isNot(Account.offlineUuid('notch')));
  });

  test('an empty list is seeded from the old single name', () async {
    final container = containerWith(MemoryAccountStore(), name: 'Steve');
    final list = await container.read(accountListProvider.future);

    // An update must not rename anyone: the name the user has been playing as becomes
    // the first account.
    expect(list.accounts.single.name, 'Steve');
    expect(list.active?.name, 'Steve');
  });

  test('accounts survive a restart, active id included', () async {
    final store = FileAccountStore(tmp);
    final first = containerWith(store);
    await first.read(accountListProvider.future);

    final notifier = first.read(accountListProvider.notifier);
    await notifier.add(const Account(id: 'a2', name: 'Alex'));
    await notifier.activate('offline-Player');

    final reopened = containerWith(FileAccountStore(tmp));
    final list = await reopened.read(accountListProvider.future);

    expect(list.accounts.map((a) => a.name), ['Player', 'Alex']);
    expect(list.active?.id, 'offline-Player');
  });

  test(
    'removing the active account falls back instead of leaving none active',
    () async {
      final container = containerWith(MemoryAccountStore());
      final list = await container.read(accountListProvider.future);
      final notifier = container.read(accountListProvider.notifier);
      await notifier.add(const Account(id: 'a2', name: 'Alex'));
      expect(container.read(accountListProvider).value?.active?.id, 'a2');

      await notifier.remove('a2');
      final after = container.read(accountListProvider).value!;

      expect(after.accounts.single.name, list.accounts.single.name);
      expect(after.active?.name, 'Player');
    },
  );

  test('ids do not collide when two accounts share a name prefix', () {
    final existing = [offlineAccount('Steve', existing: const [])];
    final second = offlineAccount('Steve', existing: existing);

    expect(second.id, isNot(existing.single.id));
  });

  test('the launch uses the active account, not the seeded name', () {
    // The launch request is where the identity is decided; everything else is bookkeeping.
    final account = const Account(id: 'a2', name: 'Alex');
    final request = buildLaunchRequest(
      instance: const Instance(id: 'demo', name: 'Demo', versionId: '1.20.1'),
      settings: AppSettings.defaults,
      version: _version(),
      account: account,
    );

    expect(request.playerName, 'Alex');
    expect(request.uuid, Account.offlineUuid('Alex'));
    expect(request.accessToken, '0');
  });

  test('a third-party account brings its own token and uuid', () {
    const account = Account(
      id: 'tp',
      name: 'Alex',
      kind: AccountKind.thirdParty,
      server: 'https://auth.example.invalid/api',
      accessToken: 'token-123',
      uuid: '11111111-2222-3333-4444-555555555555',
    );
    final request = buildLaunchRequest(
      instance: const Instance(id: 'demo', name: 'Demo', versionId: '1.20.1'),
      settings: AppSettings.defaults,
      version: _version(),
      account: account,
    );

    expect(request.playerName, 'Alex');
    expect(request.accessToken, 'token-123');
    expect(request.uuid, '11111111-2222-3333-4444-555555555555');
  });
}
