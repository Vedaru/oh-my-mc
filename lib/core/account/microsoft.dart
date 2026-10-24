import 'dart:convert';
import 'dart:io';

/// The Microsoft sign-in chain, in one place.
///
/// Five services stand between "click sign in" and a token the game accepts:
///
/// 1. **Microsoft** issues an MSA token. The device-code flow is used rather than a
///    browser redirect because a desktop app cannot keep a client secret and should not
///    open a listening socket for a redirect: the user is shown a short code, types it
///    at `microsoft.com/link`, and the app polls.
/// 2. **Xbox Live** trades the MSA token for an XBL token.
/// 3. **XSTS** authorises that token for the Minecraft relying party. This is where the
///    real failures live - no Xbox profile, a child account, a banned account - and each
///    one has to be a sentence the user can act on.
/// 4. **Minecraft services** trades the XSTS token for the game's own access token.
/// 5. **The profile endpoint** says which uuid and name the token belongs to, and a 404
///    here means the account does not own the game.
///
/// Every step is a JSON POST and every failure is one of a handful of codes, so this is
/// written as plain functions over an injected [http.Client] and a base-URL record: the
/// whole chain then runs against a fake in a test, which is the only way to keep five
/// network calls honest.
class MicrosoftAuthException implements Exception {
  const MicrosoftAuthException(this.message, {this.code});

  /// What to tell the user. Never a raw body: 'invalid_grant' is not a sentence.
  final String message;

  /// The service's own code (`BadRequest`, `2148916233`, ...) when there is one.
  final String? code;

  @override
  String toString() => code == null ? message : '$message ($code)';
}

/// One HTTP answer, reduced to what the chain reads.
///
/// The chain is five network calls whose JSON shapes are the whole feature, and the
/// launcher has no HTTP package: everything else is `dart:io`. So the transport is two
/// function types ([JsonPost], [JsonGet]) with `dart:io` implementations in this file,
/// which makes every step testable by passing closures instead of faking an
/// `HttpClient`.
class HttpReply {
  const HttpReply(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

typedef JsonPost = Future<HttpReply> Function(
  Uri url,
  Map<String, String> headers,
  Map<String, Object?> body,
);

typedef JsonGet = Future<HttpReply> Function(
  Uri url,
  Map<String, String> headers,
);

/// The real transport: one POST, body in, body out.
Future<HttpReply> ioJsonPost(
  Uri url,
  Map<String, String> headers,
  Map<String, Object?> body,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final request = await client.postUrl(url);
    headers.forEach((name, value) => request.headers.set(name, value));
    request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    return HttpReply(response.statusCode, text);
  } finally {
    client.close(force: true);
  }
}

Future<HttpReply> ioJsonGet(Uri url, Map<String, String> headers) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final request = await client.getUrl(url);
    headers.forEach((name, value) => request.headers.set(name, value));
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    return HttpReply(response.statusCode, text);
  } finally {
    client.close(force: true);
  }
}

/// Where the chain talks to. A record rather than constants so a test can point every
/// step at one fake server.
class MicrosoftEndpoints {
  const MicrosoftEndpoints({
    this.deviceCode =
        'https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode',
    this.token =
        'https://login.microsoftonline.com/consumers/oauth2/v2.0/token',
    this.xboxLive = 'https://user.auth.xboxlive.com/user/authenticate',
    this.xsts = 'https://xsts.auth.xboxlive.com/xsts/authorize',
    this.minecraftLogin =
        'https://api.minecraftservices.com/authentication/login_with_xbox',
    this.minecraftProfile =
        'https://api.minecraftservices.com/minecraft/profile',
  });

  final String deviceCode;
  final String token;
  final String xboxLive;
  final String xsts;
  final String minecraftLogin;
  final String minecraftProfile;
}

/// One pending sign-in: what the user types, and where.
class DeviceCode {
  const DeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
  });

  /// The secret this app polls with. Never shown to the user.
  final String deviceCode;

  /// The short code the user types, e.g. `K7QP-4XH2M`.
  final String userCode;

  /// Where they type it.
  final String verificationUri;

  final Duration expiresIn;

  /// The minimum gap between polls. Polling faster earns `slow_down`.
  final Duration interval;
}

/// A signed-in Microsoft account, as the launcher stores it.
class MicrosoftSession {
  const MicrosoftSession({
    required this.uuid,
    required this.name,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.skinUrl,
    this.skinVariant,
  });

  /// The player uuid, dashed, as the game and every server expect it.
  final String uuid;

  /// The in-game name.
  final String name;

  /// The Minecraft services token the game is given.
  final String accessToken;

  /// The MSA refresh token, used a day later to get a new [accessToken].
  final String refreshToken;

  /// The active skin's texture, as `textures.minecraft.net` serves it. Absent for an
  /// account that has never uploaded one, which is why the launcher has a fallback.
  final String? skinUrl;

  /// `CLASSIC` or `SLIM` (Alex). Only changes how the arms are drawn.
  final String? skinVariant;

  final DateTime expiresAt;
}

class MicrosoftAuth {
  MicrosoftAuth({
    required this.clientId,
    this.endpoints = const MicrosoftEndpoints(),
    JsonPost? post,
    JsonGet? get,
    DateTime Function()? now,
  }) : _postJson = post ?? ioJsonPost,
       _getJson = get ?? ioJsonGet,
       _now = now ?? DateTime.now;

  final JsonPost _postJson;
  final JsonGet _getJson;

  /// The Azure application id. Each launcher registers its own - Prism and MultiMC both
  /// have one - because it is the identity Microsoft shows on the consent screen.
  final String clientId;

  final MicrosoftEndpoints endpoints;
  final DateTime Function() _now;

  static const _scope = 'XboxLive.signin offline_access';

  /// Starts a sign-in: the code the user types, and the handle this app polls with.
  Future<DeviceCode> requestDeviceCode() async {
    _requireClientId();
    final body = await _post(endpoints.deviceCode, {
      'client_id': clientId,
      'scope': _scope,
    });
    return DeviceCode(
      deviceCode: _string(body, 'device_code'),
      userCode: _string(body, 'user_code'),
      verificationUri: _string(body, 'verification_uri'),
      expiresIn: Duration(seconds: _int(body, 'expires_in', 900)),
      interval: Duration(seconds: _int(body, 'interval', 5)),
    );
  }

  /// Polls until the user finishes, the code expires, or they decline.
  ///
  /// [onPending] runs between polls so a dialog can keep saying "waiting". [cancelled]
  /// lets the dialog close without leaving a poll running forever.
  Future<MicrosoftSession> waitForSignIn(
    DeviceCode code, {
    Future<void> Function()? onPending,
    bool Function()? cancelled,
  }) async {
    final deadline = _now().add(code.expiresIn);
    var interval = code.interval;
    while (_now().isBefore(deadline)) {
      if (cancelled?.call() ?? false) {
        throw const MicrosoftAuthException('Sign-in cancelled.');
      }
      await Future<void>.delayed(interval);
      if (cancelled?.call() ?? false) {
        throw const MicrosoftAuthException('Sign-in cancelled.');
      }
      final response = await _postJson(
        Uri.parse(endpoints.token),
        _jsonHeaders,
        {
          'client_id': clientId,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
          'device_code': code.deviceCode,
        },
      );
      switch (_errorCode(response)) {
        case null:
          final body = _decode(response);
          return _finishWithMsa(
            _string(body, 'access_token'),
            _string(body, 'refresh_token'),
          );
        // Expected: the user has not typed the code yet.
        case 'authorization_pending':
          await onPending?.call();
        // The server asked for a slower poll; honour it or be locked out.
        case 'slow_down':
          interval += const Duration(seconds: 5);
          await onPending?.call();
        case 'expired_token':
          throw const MicrosoftAuthException(
            'The code expired before it was used. Start again.',
            code: 'expired_token',
          );
        case 'authorization_declined':
          throw const MicrosoftAuthException(
            'The sign-in was declined on the Microsoft page.',
            code: 'authorization_declined',
          );
        default:
          throw MicrosoftAuthException(
            'Microsoft refused the sign-in.',
            code: _errorCode(response),
          );
      }
    }
    throw const MicrosoftAuthException(
      'The code expired before it was used. Start again.',
      code: 'expired_token',
    );
  }

  /// A new session from a stored refresh token.
  ///
  /// This is what makes a Microsoft account usable a week later: the game token lives
  /// about a day, the refresh token months.
  Future<MicrosoftSession> refresh(String refreshToken) async {
    _requireClientId();
    final response = await _postJson(Uri.parse(endpoints.token), _jsonHeaders, {
      'client_id': clientId,
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'scope': _scope,
    });
    if (_errorCode(response) case final code?) {
      throw MicrosoftAuthException(
        code == 'invalid_grant'
            ? 'The saved Microsoft session expired. Sign in again.'
            : 'Microsoft refused to renew the session.',
        code: code,
      );
    }
    final body = _decode(response);
    return _finishWithMsa(
      _string(body, 'access_token'),
      // A refresh response may omit the refresh token; the caller keeps the old one.
      _string(body, 'refresh_token', fallback: refreshToken),
    );
  }

  /// The rest of the chain: MSA -> XBL -> XSTS -> Minecraft -> profile.
  Future<MicrosoftSession> _finishWithMsa(
    String msaToken,
    String refreshToken,
  ) async {
    final xbl = await _post(endpoints.xboxLive, {
      'Properties': {
        'AuthMethod': 'RPS',
        'SiteName': 'user.auth.xboxlive.com',
        'RpsTicket': 'd=$msaToken',
      },
      'RelyingParty': 'http://auth.xboxlive.com',
      'TokenType': 'JWT',
    });
    final xblToken = _string(xbl, 'Token');
    final userHash = _userHash(xbl);

    final xstsResponse = await _postJson(
      Uri.parse(endpoints.xsts),
      _jsonHeaders,
      {
        'Properties': {
          'SandboxId': 'RETAIL',
          'UserTokens': [xblToken],
        },
        'RelyingParty': 'rp://api.minecraftservices.com/',
        'TokenType': 'JWT',
      },
    );
    // XSTS failures are the informative ones, and they arrive as `XErr` with a 401.
    final xerr = _xerr(xstsResponse);
    if (xerr != null) {
      throw MicrosoftAuthException(_xerrMessage(xerr), code: xerr);
    }
    final xsts = _decode(xstsResponse);
    final xstsToken = _string(xsts, 'Token');

    final mc = await _post(endpoints.minecraftLogin, {
      'identityToken': 'XBL3.0 x=$userHash;$xstsToken',
    });
    final accessToken = _string(mc, 'access_token');
    final expiresIn = Duration(seconds: _int(mc, 'expires_in', 86400));

    final profile = await _getJson(Uri.parse(endpoints.minecraftProfile), {
      'Authorization': 'Bearer $accessToken',
    });
    if (profile.statusCode == 404) {
      throw const MicrosoftAuthException(
        'This Microsoft account does not own Minecraft: Java Edition.',
        code: 'profile_not_found',
      );
    }
    if (profile.statusCode != 200) {
      throw MicrosoftAuthException(
        'Minecraft services refused the session.',
        code: 'profile_${profile.statusCode}',
      );
    }
    final body = _decode(profile);
    // The profile carries the skins the same way the game reads them: a list with one
    // entry in the `ACTIVE` state.
    final active = _activeSkin(body);
    return MicrosoftSession(
      // The profile endpoint answers with 32 hex characters; the game, the server list
      // and every world folder want the dashed form.
      uuid: _dashed(_string(body, 'id')),
      name: _string(body, 'name'),
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: _now().add(expiresIn),
      skinUrl: active?['url'] as String?,
      skinVariant: active?['variant'] as String?,
    );
  }

  /// The `ACTIVE` entry of the profile's `skins` list, or null.
  ///
  /// Reading `skins.first` would be wrong: the list keeps every skin the account has
  /// worn, and the first one is the oldest.
  Map<String, Object?>? _activeSkin(Map<String, Object?> profile) {
    final skins = profile['skins'];
    if (skins is! List) return null;
    for (final skin in skins) {
      if (skin is Map<String, Object?> && skin['state'] == 'ACTIVE') {
        return skin;
      }
    }
    return null;
  }

  void _requireClientId() {
    if (clientId.trim().isEmpty) {
      throw const MicrosoftAuthException(
        'No Azure application id is configured. Microsoft sign-in needs one - the '
        'launcher has to identify itself to Microsoft - and it is a per-launcher '
        'registration, so it cannot be shipped.',
        code: 'missing_client_id',
      );
    }
  }

  Future<Map<String, Object?>> _post(
    String url,
    Map<String, Object?> body,
  ) async {
    final response = await _postJson(Uri.parse(url), _jsonHeaders, body);
    if (response.statusCode >= 400) {
      throw MicrosoftAuthException(
        'Microsoft refused the sign-in.',
        code: _errorCode(response) ?? '${response.statusCode}',
      );
    }
    return _decode(response);
  }

  /// `{ "error": "authorization_pending" }` - or null on success.
  String? _errorCode(HttpReply response) {
    if (response.statusCode < 400) return null;
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['error'] is String) {
        return body['error'] as String;
      }
    } on FormatException {
      // Not JSON: a proxy error page, most likely.
    }
    return '${response.statusCode}';
  }

  /// XSTS answers 401 with `XErr` in the body and a human `Message`.
  String? _xerr(HttpReply response) {
    if (response.statusCode != 401) return null;
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['XErr'] != null) {
        return '${body['XErr']}';
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  String _xerrMessage(String xerr) => switch (xerr) {
    // 2148916233: the Microsoft account has never played an Xbox game.
    '2148916233' =>
      'This Microsoft account has no Xbox profile yet. Sign in at '
          'xbox.com once, then try again.',
    // 2148916238: under-18 account, needs a family group.
    '2148916238' =>
      'This is a child account. An adult in its Microsoft family '
          'group has to allow Minecraft.',
    '2148916235' => 'Xbox Live is not available in this account\'s country.',
    '2148916236' || '2148916237' =>
      'This account needs to pass Xbox age '
          'verification before it can play.',
    _ => 'Xbox Live refused the account.',
  };

  /// `1111...` (32 hex) -> `1111-1111-...`. Already-dashed input is left alone, because
  /// being tolerant here costs nothing and guessing wrong costs a broken session.
  static String _dashed(String id) {
    if (id.contains('-') || id.length != 32) return id;
    return '${id.substring(0, 8)}-${id.substring(8, 12)}-'
        '${id.substring(12, 16)}-${id.substring(16, 20)}-${id.substring(20)}';
  }

  String _userHash(Map<String, Object?> xbl) {
    final claims = xbl['DisplayClaims'];
    if (claims is Map) {
      final xui = claims['xui'];
      if (xui is List && xui.isNotEmpty) {
        final first = xui.first;
        if (first is Map && first['uhs'] is String) {
          return first['uhs'] as String;
        }
      }
    }
    throw const MicrosoftAuthException(
      'Xbox Live answered without a user hash.',
      code: 'missing_uhs',
    );
  }

  static const _jsonHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Map<String, Object?> _decode(HttpReply response) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const MicrosoftAuthException(
        'A sign-in service answered with something that is not an object.',
        code: 'bad_response',
      );
    }
    return decoded;
  }

  String _string(Map<String, Object?> json, String key, {String? fallback}) {
    final value = json[key];
    if (value is String && value.isNotEmpty) return value;
    if (fallback != null) return fallback;
    throw MicrosoftAuthException(
      'A sign-in service answered without `$key`.',
      code: 'missing_$key',
    );
  }

  int _int(Map<String, Object?> json, String key, int fallback) {
    final value = json[key];
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }
}
