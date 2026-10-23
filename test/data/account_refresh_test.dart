import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/account/account.dart';
import 'package:oh_my_mc/core/account/microsoft.dart';
import 'package:oh_my_mc/data/account_store.dart';
import 'package:oh_my_mc/data/microsoft_providers.dart';

/// A Microsoft token lasts about a day; the launcher's job is that the second day looks
/// exactly like the first. These tests are about *when* renewal happens and what happens
/// when it fails - the chain itself is covered in `microsoft_test.dart`.
class _FakeAuth extends MicrosoftAuth {
  _FakeAuth({this.session, this.failure}) : super(clientId: 'x');

  final MicrosoftSession? session;
  final MicrosoftAuthException? failure;
  var refreshCalls = 0;

  @override
  Future<MicrosoftSession> refresh(String refreshToken) async {
    refreshCalls++;
    final failure = this.failure;
    if (failure != null) throw failure;
    return session!;
  }
}

void main() {
  late Directory data;
  late FileAccountStore store;

  setUp(() async {
    data = await Directory.systemTemp.createTemp('ms-refresh');
    store = FileAccountStore(data);
  });

  tearDown(() async {
    if (data.existsSync()) await data.delete(recursive: true);
  });

  Account expiring({String refreshToken = 'refresh-1'}) => Account(
    id: 'microsoft-uuid',
    name: 'Steve',
    kind: AccountKind.microsoft,
    uuid: '11111111-2222-3333-4444-555555555555',
    accessToken: 'old-token',
    refreshToken: refreshToken,
    // Inside the five-minute early window: renewal is due.
    expiresAt: DateTime.now().add(const Duration(minutes: 2)),
  );

  test('a fresh token is left alone', () async {
    final auth = _FakeAuth(session: null);
    final account = Account(
      id: 'microsoft-uuid',
      name: 'Steve',
      kind: AccountKind.microsoft,
      accessToken: 'good',
      refreshToken: 'refresh-1',
      expiresAt: DateTime.now().add(const Duration(hours: 20)),
    );

    final result = await AccountRefresher(store, auth).refreshIfNeeded(account);

    expect(auth.refreshCalls, 0);
    expect(result.accessToken, 'good');
  });

  test('an expiring token is renewed and written back', () async {
    final account = expiring();
    await store.write(AccountList(accounts: [account], activeId: account.id));
    final auth = _FakeAuth(
      session: MicrosoftSession(
        uuid: account.uuid!,
        name: 'Steve',
        accessToken: 'new-token',
        refreshToken: 'refresh-2',
        expiresAt: DateTime.now().add(const Duration(hours: 23)),
      ),
    );

    final result = await AccountRefresher(store, auth).refreshIfNeeded(account);

    expect(auth.refreshCalls, 1);
    expect(result.accessToken, 'new-token');
    // The new refresh token is the one that has months left on it; keeping the old one
    // is how an account dies quietly a week later.
    expect(result.refreshToken, 'refresh-2');
    expect(result.needsRefresh, isFalse);

    final stored = await store.read();
    expect(stored.accounts.single.accessToken, 'new-token');
    expect(stored.activeId, account.id);
  });

  test(
    'a failed renewal keeps the old session instead of blocking the launch',
    () async {
      final account = expiring();
      await store.write(AccountList(accounts: [account], activeId: account.id));
      final auth = _FakeAuth(
        failure: const MicrosoftAuthException(
          'The saved Microsoft session expired. Sign in again.',
          code: 'invalid_grant',
        ),
      );

      final result = await AccountRefresher(
        store,
        auth,
      ).refreshIfNeeded(account);

      // The launch still gets an account: a stale token fails inside the game with a
      // message, a launcher that refuses to start at all is worse.
      expect(result.accessToken, 'old-token');
      expect((await store.read()).accounts.single.accessToken, 'old-token');
    },
  );

  test('an offline account never enters the refresh path', () async {
    final auth = _FakeAuth(session: null);
    const account = Account(id: 'offline-Steve', name: 'Steve');

    final result = await AccountRefresher(store, auth).refreshIfNeeded(account);

    expect(auth.refreshCalls, 0);
    expect(result.id, 'offline-Steve');
  });

  test('the account file round-trips the refresh token and expiry', () async {
    await store.write(
      AccountList(accounts: [expiring()], activeId: 'microsoft-uuid'),
    );
    final read = (await store.read()).accounts.single;

    expect(read.kind, AccountKind.microsoft);
    expect(read.refreshToken, 'refresh-1');
    expect(read.expiresAt, isNotNull);
    // Locally derived, not the raw UTC string: `needsRefresh` compares with `now`.
    expect(read.expiresAt!.isUtc, isFalse);
  });
}
