import 'dart:convert';

import 'package:crypto/crypto.dart';

/// How an account proves who it is.
enum AccountKind {
  /// A name and nothing else - the game's own offline mode. The UUID is derived from
  /// the name, so worlds and inventories stay stable across launcher restarts.
  offline,

  /// A third-party authentication server (authlib-injector / Yggdrasil-compatible).
  /// The session comes from that server; the launch gets its `accessToken` and `uuid`.
  thirdParty,

  /// A real Microsoft account. The game only accepts it with a
  /// `services.minecraft.accessToken` that expires in about a day, so this kind carries
  /// the refresh token and the expiry the others do not need: a token that has quietly
  /// died is the difference between "it just works tomorrow" and "login again".
  microsoft,
}

/// One identity the launcher can start the game as.
///
/// Accounts are a list because a player is not one name: single-player worlds belong to
/// one, a friend's server to another, a third-party server to a third. The old model -
/// `AppSettings.playerName`, one string - is kept as the *seed* for the first account so
/// an existing install does not lose its identity when this lands.
class Account {
  const Account({
    required this.id,
    required this.name,
    this.kind = AccountKind.offline,
    this.server,
    this.accessToken,
    this.uuid,
    this.refreshToken,
    this.expiresAt,
    this.skinUrl,
    this.skinVariant,
  });

  /// Stable id for the account itself (not the player uuid): renames keep the account.
  final String id;

  /// The name the game shows.
  final String name;

  final AccountKind kind;

  /// The API root of a third-party authentication server.
  final String? server;

  /// The session token a third-party server issued. Null for an offline account, whose
  /// token is the string `0`.
  final String? accessToken;

  /// The uuid the server assigned, when there is one. Offline accounts derive it.
  final String? uuid;

  /// The token to trade for a new [accessToken] once it expires. Microsoft accounts
  /// only; it is never sent to the game.
  final String? refreshToken;

  /// When [accessToken] stops being accepted. Null means "no known expiry".
  final DateTime? expiresAt;

  /// The account's skin texture, when it has one. Offline accounts never do: a skin is
  /// something a server-verified identity owns.
  final String? skinUrl;

  /// `CLASSIC` (Steve-shaped) or `SLIM` (Alex-shaped).
  final String? skinVariant;

  bool get isOffline => kind == AccountKind.offline;

  /// A Microsoft session is refreshed a little early rather than exactly on the dot:
  /// the clock that matters is the server's, and a launch that starts one second before
  /// expiry fails during the handshake instead of fetching a new token.
  bool get needsRefresh {
    if (kind != AccountKind.microsoft) return false;
    final expiry = expiresAt;
    if (expiry == null) return false;
    return DateTime.now().isAfter(expiry.subtract(const Duration(minutes: 5)));
  }

  /// Whether this account can still be used without the user signing in again.
  bool get canRefresh =>
      kind == AccountKind.microsoft && (refreshToken?.isNotEmpty ?? false);

  /// What the game is told. An offline account's UUID is `OfflinePlayer:<name>` hashed,
  /// which is what the game itself does in offline mode.
  String get effectiveUuid => uuid ?? offlineUuid(name);

  /// Offline accounts have no secret; the game accepts `0` for them.
  String get effectiveAccessToken => accessToken ?? '0';

  /// `Steve (offline)` / `Steve (authlib.example.net)`.
  String get describe => switch (kind) {
    AccountKind.offline => '$name · 离线',
    AccountKind.thirdParty => server == null ? name : '$name · $server',
    AccountKind.microsoft => '$name · Microsoft',
  };

  Account copyWith({
    String? name,
    String? accessToken,
    String? uuid,
    String? refreshToken,
    DateTime? expiresAt,
    String? skinUrl,
    String? skinVariant,
  }) => Account(
    id: id,
    name: name ?? this.name,
    kind: kind,
    server: server,
    accessToken: accessToken ?? this.accessToken,
    uuid: uuid ?? this.uuid,
    refreshToken: refreshToken ?? this.refreshToken,
    expiresAt: expiresAt ?? this.expiresAt,
    skinUrl: skinUrl ?? this.skinUrl,
    skinVariant: skinVariant ?? this.skinVariant,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    if (server != null) 'server': server,
    if (accessToken != null) 'accessToken': accessToken,
    if (uuid != null) 'uuid': uuid,
    if (refreshToken != null) 'refreshToken': refreshToken,
    if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
    if (skinUrl != null) 'skinUrl': skinUrl,
    if (skinVariant != null) 'skinVariant': skinVariant,
  };

  factory Account.fromJson(Map<String, Object?> json) => Account(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    kind: switch (json['kind']) {
      'thirdParty' => AccountKind.thirdParty,
      'microsoft' => AccountKind.microsoft,
      _ => AccountKind.offline,
    },
    server: json['server'] as String?,
    accessToken: json['accessToken'] as String?,
    uuid: json['uuid'] as String?,
    refreshToken: json['refreshToken'] as String?,
    expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? '')?.toLocal(),
    skinUrl: json['skinUrl'] as String?,
    skinVariant: json['skinVariant'] as String?,
  );

  /// A uuid the game recognises for [name] in offline mode.
  ///
  /// `md5("OfflinePlayer:" + name)` with the version and variant nibbles patched, which
  /// is what the game does without a session server. Same name in, same uuid out - that
  /// is the whole point: inventories and worlds are keyed by it.
  static String offlineUuid(String name) {
    final hash = md5.convert(utf8.encode('OfflinePlayer:$name')).bytes;
    final chars = [
      for (final byte in hash)
        ...byte.toRadixString(16).padLeft(2, '0').split(''),
    ];
    // Bytes 6 and 8 hold the version and variant nibbles, so patch the hex digit at
    // char 12 and 16. Splicing strings is what got this wrong the first time.
    chars[12] = '3';
    chars[16] = ((int.parse(chars[16], radix: 16) & 0x3) | 0x8).toRadixString(
      16,
    );
    final hex = chars.join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
