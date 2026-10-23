import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/account/account.dart';
import 'account_store.dart';
import 'launch_factory.dart';

/// The account store, over the launcher's data directory.
final accountStoreProvider = Provider<AccountStore>((ref) {
  final paths = ref.watch(launcherPathsProvider);
  return FileAccountStore(paths.data);
});

/// The accounts, with the legacy single name migrated into the first one.
///
/// `AppSettings.playerName` predates accounts. A player who has been launching as
/// "Steve" must not be renamed to "Player" by an update, so an empty account list is
/// seeded from that name once, and the settings field stays as the seed for a fresh
/// install.
class AccountListNotifier extends AsyncNotifier<AccountList> {
  @override
  Future<AccountList> build() async {
    final store = ref.watch(accountStoreProvider);
    final loaded = await store.read();
    if (loaded.accounts.isNotEmpty) return loaded;

    final name = ref.read(appSettingsProvider).playerName;
    final seeded = AccountList(
      accounts: [Account(id: 'offline-$name', name: name)],
      activeId: 'offline-$name',
    );
    await store.write(seeded);
    return seeded;
  }

  Future<void> add(Account account) async {
    final current = state.value ?? const AccountList();
    final next = AccountList(
      accounts: [...current.accounts, account],
      // The account just added becomes active: that is the intent of adding it.
      activeId: account.id,
    );
    state = AsyncValue.data(next);
    await ref.read(accountStoreProvider).write(next);
  }

  Future<void> activate(String id) async {
    final current = state.value ?? const AccountList();
    if (!current.accounts.any((account) => account.id == id)) return;
    final next = AccountList(accounts: current.accounts, activeId: id);
    state = AsyncValue.data(next);
    await ref.read(accountStoreProvider).write(next);
  }

  Future<void> remove(String id) async {
    final current = state.value ?? const AccountList();
    final remaining = [
      for (final account in current.accounts)
        if (account.id != id) account,
    ];
    final next = AccountList(
      accounts: remaining,
      activeId: current.activeId == id
          ? (remaining.isEmpty ? null : remaining.first.id)
          : current.activeId,
    );
    state = AsyncValue.data(next);
    await ref.read(accountStoreProvider).write(next);
  }

  Future<void> rename(String id, String name) async {
    final current = state.value ?? const AccountList();
    final next = AccountList(
      accounts: [
        for (final account in current.accounts)
          account.id == id ? account.copyWith(name: name) : account,
      ],
      activeId: current.activeId,
    );
    state = AsyncValue.data(next);
    await ref.read(accountStoreProvider).write(next);
  }
}

final accountListProvider =
    AsyncNotifierProvider<AccountListNotifier, AccountList>(
      AccountListNotifier.new,
    );

/// The account a launch uses, or null while the list is loading.
final activeAccountProvider = Provider<Account?>((ref) {
  final list = ref.watch(accountListProvider);
  return list is AsyncData<AccountList> ? list.value.active : null;
});

/// A new offline account, with an id that cannot collide with an existing one.
Account offlineAccount(String name, {required Iterable<Account> existing}) {
  final base = 'offline-$name';
  var id = base;
  var suffix = 2;
  final taken = {for (final account in existing) account.id};
  while (taken.contains(id)) {
    id = '$base-$suffix';
    suffix++;
  }
  return Account(id: id, name: name);
}
