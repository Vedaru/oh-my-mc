import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/account/account.dart';
import '../core/account/microsoft.dart';
import 'account_providers.dart';
import 'account_store.dart';

/// The Microsoft chain, wired to the configured application id.
///
/// Overridable so a widget test can answer with a fake session instead of polling
/// Microsoft: the dialog's job is what it shows and what it stores, not the five network
/// calls (`test/core/account/microsoft_test.dart` owns those).
final microsoftAuthProvider = Provider<MicrosoftAuth>((ref) {
  final clientId = ref.watch(
    appSettingsProvider.select((settings) => settings.microsoftClientId),
  );
  return MicrosoftAuth(clientId: clientId);
});

/// Turns the chain's answer into an account the rest of the launcher understands.
Account accountFromSession(MicrosoftSession session) => Account(
  // Keyed by uuid, not by name: a player who changes their Minecraft name keeps their
  // account, and signing in twice does not stack a second row.
  id: 'microsoft-${session.uuid}',
  name: session.name,
  kind: AccountKind.microsoft,
  uuid: session.uuid,
  accessToken: session.accessToken,
  refreshToken: session.refreshToken,
  expiresAt: session.expiresAt,
  skinUrl: session.skinUrl,
  skinVariant: session.skinVariant,
);

/// Keeps a Microsoft account usable across days.
///
/// The game's token lives about 24 hours and the refresh token months, so a launch a week
/// later has to renew rather than fail. Returns the account unchanged when there is
/// nothing to do - and when renewal fails, because a launch that works with a stale token
/// beats a launch that refuses over one it could not renew.
class AccountRefresher {
  AccountRefresher(this._store, this._auth);

  final AccountStore _store;
  final MicrosoftAuth _auth;

  Future<Account> refreshIfNeeded(Account account) async {
    if (!account.needsRefresh || !account.canRefresh) return account;
    final MicrosoftSession session;
    try {
      session = await _auth.refresh(account.refreshToken!);
    } on MicrosoftAuthException {
      return account;
    }
    final renewed = account.copyWith(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      uuid: session.uuid,
      name: session.name,
      expiresAt: session.expiresAt,
    );
    final list = await _store.read();
    await _store.write(
      AccountList(
        accounts: [
          for (final existing in list.accounts)
            if (existing.id == renewed.id) renewed else existing,
        ],
        activeId: list.activeId,
      ),
    );
    return renewed;
  }
}

final accountRefresherProvider = Provider<AccountRefresher>(
  (ref) => AccountRefresher(
    ref.watch(accountStoreProvider),
    ref.watch(microsoftAuthProvider),
  ),
);
