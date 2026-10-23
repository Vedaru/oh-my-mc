import 'dart:convert';
import 'dart:io';

import 'account.dart';

/// The server refused the login, with its own reason.
///
/// Third-party servers answer with a machine code and a message meant for the player
/// (`invalid credentials`, `banned`); passing that through is the difference between "it
/// did not work" and "your password was wrong".
class YggdrasilException implements Exception {
  const YggdrasilException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// A session from a Yggdrasil-compatible authentication server (authlib-injector).
///
/// This is the login half of the account kinds: `authenticate` turns a name and password
/// into the `accessToken` and player uuid the launch needs. Nothing is persisted except
/// the result - a password never touches the disk.
class YggdrasilClient {
  const YggdrasilClient({this.timeout = const Duration(seconds: 15)});

  final Duration timeout;

  /// Logs in against [apiRoot] (the server's API root, e.g.
  /// `https://auth.example.net/api/yggdrasil`).
  Future<Account> authenticate({
    required String apiRoot,
    required String username,
    required String password,
  }) async {
    final root = _normalise(apiRoot);
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.postUrl(
        Uri.parse('$root/authserver/authenticate'),
      );
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'agent': {'name': 'Minecraft', 'version': 1},
          'username': username,
          'password': password,
          'requestUser': false,
        }),
      );
      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join();

      final json = _decode(body);
      if (response.statusCode != HttpStatus.ok) {
        throw YggdrasilException(
          _message(json) ??
              'the server refused the login (${response.statusCode})',
          code: json?['error'] as String?,
        );
      }
      final token = json?['accessToken'];
      final profile = json?['selectedProfile'];
      if (token is! String || profile is! Map) {
        throw const YggdrasilException(
          'the server did not return a session for a player',
        );
      }
      final name = profile['name'];
      final id = profile['id'];
      if (name is! String || id is! String) {
        throw const YggdrasilException(
          'the server returned an incomplete profile',
        );
      }
      return Account(
        // The account id is the player uuid here: the server is the authority on who
        // this is, and a uuid cannot collide with an offline account's name id.
        id: 'tp-$id',
        name: name,
        kind: AccountKind.thirdParty,
        server: root,
        accessToken: token,
        uuid: _dashedUuid(id),
      );
    } on YggdrasilException {
      rethrow;
    } on Object catch (error) {
      throw YggdrasilException('could not reach $root: $error');
    } finally {
      client.close(force: true);
    }
  }

  /// `https://host/api/yggdrasil/` → `https://host/api/yggdrasil`, and a bare host gets
  /// the conventional `/api/yggdrasil` path appended.
  static String _normalise(String apiRoot) {
    var root = apiRoot.trim();
    while (root.endsWith('/')) {
      root = root.substring(0, root.length - 1);
    }
    if (!root.startsWith('http://') && !root.startsWith('https://')) {
      root = 'https://$root';
    }
    final uri = Uri.tryParse(root);
    if (uri != null && (uri.path.isEmpty || uri.path == '/')) {
      root = '$root/api/yggdrasil';
    }
    return root;
  }

  static Map<String, dynamic>? _decode(String body) {
    try {
      final json = jsonDecode(body);
      return json is Map<String, dynamic> ? json : null;
    } on FormatException {
      return null;
    }
  }

  static String? _message(Map<String, dynamic>? json) {
    final message = json?['errorMessage'] ?? json?['error'];
    return message is String && message.trim().isNotEmpty ? message : null;
  }

  /// Profiles come back without dashes; the launch wants the canonical form.
  static String _dashedUuid(String id) {
    final hex = id.replaceAll('-', '');
    if (hex.length != 32) return id;
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
