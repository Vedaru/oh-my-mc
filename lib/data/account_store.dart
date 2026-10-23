import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/account/account.dart';

/// The accounts on this machine, and which one is active.
class AccountList {
  const AccountList({this.accounts = const [], this.activeId});

  final List<Account> accounts;

  /// The account the launcher starts the game as. Null when there is none (a fresh
  /// install, or the active account was removed).
  final String? activeId;

  Account? get active {
    for (final account in accounts) {
      if (account.id == activeId) return account;
    }
    // An active id that no longer exists falls back to the first account rather than
    // to null: a list with one account has an obvious answer.
    return accounts.isEmpty ? null : accounts.first;
  }

  Map<String, Object?> toJson() => {
    'activeId': ?activeId,
    'accounts': [for (final account in accounts) account.toJson()],
  };

  factory AccountList.fromJson(Map<String, Object?> json) {
    final accounts = <Account>[];
    final raw = json['accounts'];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is Map<String, Object?>) {
          final account = Account.fromJson(entry);
          if (account.id.isNotEmpty && account.name.isNotEmpty) {
            accounts.add(account);
          }
        }
      }
    }
    return AccountList(
      accounts: accounts,
      activeId: json['activeId'] as String?,
    );
  }
}

/// Where the account list is kept.
///
/// A file of its own, not settings: a token is not a preference, and mixing them would
/// put a credential in the same blob the UI rewrites on every slider drag.
abstract class AccountStore {
  Future<AccountList> read();
  Future<void> write(AccountList list);
}

class FileAccountStore implements AccountStore {
  const FileAccountStore(this.directory);

  final Directory directory;

  File get _file => File(p.join(directory.path, 'accounts.json'));

  @override
  Future<AccountList> read() async {
    try {
      if (!await _file.exists()) return const AccountList();
      final json = jsonDecode(await _file.readAsString());
      if (json is! Map<String, Object?>) return const AccountList();
      return AccountList.fromJson(json);
    } on Object {
      // A corrupt accounts file is not worth failing the launcher over: the user can
      // sign in again, and a crash on start is not a recovery path.
      return const AccountList();
    }
  }

  @override
  Future<void> write(AccountList list) async {
    await directory.create(recursive: true);
    // Write-then-rename: a crash mid-write must not leave a half-written list where the
    // launcher expects its identities.
    final temp = File('${_file.path}.part');
    await temp.writeAsString(jsonEncode(list.toJson()));
    await temp.rename(_file.path);
  }
}

/// In-memory store for tests and for a window that has no data directory.
class MemoryAccountStore implements AccountStore {
  MemoryAccountStore([this._list = const AccountList()]);

  AccountList _list;

  @override
  Future<AccountList> read() async => _list;

  @override
  Future<void> write(AccountList list) async => _list = list;
}
