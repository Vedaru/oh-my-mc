import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/account/microsoft.dart';

/// The whole Microsoft chain, with the network replaced by closures.
///
/// Five services each answer one JSON shape; the only way to keep that honest is to
/// drive the real code through those shapes - including the failures, which are the
/// part a user actually meets (no Xbox profile, a child account, no game on the
/// account).
void main() {
  const clientId = 'test-client-id';

  /// A transport that records every call and answers from [handler].
  ({JsonPost post, JsonGet get, List<String> calls}) transport(
    Future<HttpReply> Function(Uri url, Map<String, Object?>? body) handler,
  ) {
    final calls = <String>[];
    return (
      calls: calls,
      post: (url, headers, body) {
        calls.add('POST ${url.path}');
        return handler(url, body);
      },
      get: (url, headers) {
        calls.add('GET ${url.path}');
        return handler(url, null);
      },
    );
  }

  HttpReply json(Object body, [int status = 200]) =>
      HttpReply(status, jsonEncode(body));

  MicrosoftAuth auth(JsonPost post, JsonGet get, {String id = clientId}) =>
      MicrosoftAuth(clientId: id, post: post, get: get);

  /// The happy path's answers, keyed by path suffix.
  Future<HttpReply> Function(Uri, Map<String, Object?>?) happyPath({
    Map<String, Object?>? profile,
    int profileStatus = 200,
  }) {
    return (url, body) async {
      final path = url.path;
      if (path.endsWith('devicecode')) {
        return json({
          'device_code': 'dev-1',
          'user_code': 'K7QP-4XH2M',
          'verification_uri': 'https://microsoft.com/link',
          'expires_in': 900,
          'interval': 1,
        });
      }
      if (path.endsWith('/token')) {
        final grant = body?['grant_type'] as String? ?? '';
        return json({
          'access_token': grant.contains('device_code') ? 'msa-1' : 'msa-2',
          'refresh_token': 'refresh-1',
          'expires_in': 3600,
        });
      }
      if (path.endsWith('/user/authenticate')) {
        return json({
          'Token': 'xbl-token',
          'DisplayClaims': {
            'xui': [
              {'uhs': 'uhs-1'},
            ],
          },
        });
      }
      if (path.endsWith('/xsts/authorize')) {
        return json({'Token': 'xsts-token'});
      }
      if (path.endsWith('/login_with_xbox')) {
        return json({'access_token': 'mc-token', 'expires_in': 86400});
      }
      if (path.endsWith('/minecraft/profile')) {
        return json(
          profile ??
              {'id': '11111111222233334444555555555555', 'name': 'Steve'},
          profileStatus,
        );
      }
      return json({'error': 'unexpected path $path'}, 404);
    };
  }

  group('device code', () {
    test('asks for a code and hands back what the user has to type', () async {
      final t = transport(happyPath());
      final code = await auth(t.post, t.get).requestDeviceCode();

      expect(code.userCode, 'K7QP-4XH2M');
      expect(code.verificationUri, 'https://microsoft.com/link');
      expect(code.interval, const Duration(seconds: 1));
      expect(code.expiresIn, const Duration(seconds: 900));
    });

    test('refuses to start without an application id', () async {
      final t = transport(happyPath());
      await expectLater(
        auth(t.post, t.get, id: '  ').requestDeviceCode(),
        throwsA(
          isA<MicrosoftAuthException>().having(
            (e) => e.code,
            'code',
            'missing_client_id',
          ),
        ),
      );
      // And it must not have touched the network to find that out.
      expect(t.calls, isEmpty);
    });

    test(
      'a pending poll is not a failure, and the next one succeeds',
      () async {
        var polls = 0;
        final happy = happyPath();
        final t = transport((url, body) async {
          if (url.path.endsWith('/token')) {
            polls++;
            if (polls == 1) {
              return json({'error': 'authorization_pending'}, 400);
            }
          }
          return happy(url, body);
        });
        final code = await auth(t.post, t.get).requestDeviceCode();
        final session = await auth(t.post, t.get).waitForSignIn(code);

        expect(polls, 2);
        expect(session.name, 'Steve');
        expect(session.accessToken, 'mc-token');
      },
    );

    test('a declined sign-in says so instead of retrying forever', () async {
      final happy = happyPath();
      final t = transport((url, body) async {
        if (url.path.endsWith('/token')) {
          return json({'error': 'authorization_declined'}, 400);
        }
        return happy(url, body);
      });
      final code = await auth(t.post, t.get).requestDeviceCode();
      await expectLater(
        auth(t.post, t.get).waitForSignIn(code),
        throwsA(
          isA<MicrosoftAuthException>().having(
            (e) => e.code,
            'code',
            'authorization_declined',
          ),
        ),
      );
    });
  });

  group('the Xbox chain', () {
    test('walks MSA -> XBL -> XSTS -> Minecraft -> profile in order', () async {
      final t = transport(happyPath());
      final code = await auth(t.post, t.get).requestDeviceCode();
      final session = await auth(t.post, t.get).waitForSignIn(code);

      expect(
        t.calls,
        containsAllInOrder([
          'POST /consumers/oauth2/v2.0/token',
          'POST /user/authenticate',
          'POST /xsts/authorize',
          'POST /authentication/login_with_xbox',
          'GET /minecraft/profile',
        ]),
      );
      // The dashed uuid the game wants, from the profile's undashed id.
      expect(session.uuid, '11111111-2222-3333-4444-555555555555');
      expect(session.refreshToken, 'refresh-1');
      expect(
        session.expiresAt.difference(DateTime.now()).inHours,
        greaterThan(20),
      );
    });

    test(
      'an account with no Xbox profile gets the sentence that fixes it',
      () async {
        final happy = happyPath();
        final t = transport((url, body) async {
          if (url.path.endsWith('/xsts/authorize')) {
            return json({'XErr': 2148916233, 'Message': ''}, 401);
          }
          return happy(url, body);
        });
        final code = await auth(t.post, t.get).requestDeviceCode();
        await expectLater(
          auth(t.post, t.get).waitForSignIn(code),
          throwsA(
            isA<MicrosoftAuthException>()
                .having((e) => e.code, 'code', '2148916233')
                .having((e) => e.message, 'message', contains('xbox.com')),
          ),
        );
      },
    );

    test('a child account points at the family group', () async {
      final happy = happyPath();
      final t = transport((url, body) async {
        if (url.path.endsWith('/xsts/authorize')) {
          return json({'XErr': 2148916238, 'Message': ''}, 401);
        }
        return happy(url, body);
      });
      final code = await auth(t.post, t.get).requestDeviceCode();
      await expectLater(
        auth(t.post, t.get).waitForSignIn(code),
        throwsA(
          isA<MicrosoftAuthException>().having(
            (e) => e.message,
            'message',
            contains('family'),
          ),
        ),
      );
    });

    test(
      'an account that does not own the game is told exactly that',
      () async {
        final t = transport(happyPath(profileStatus: 404));
        final code = await auth(t.post, t.get).requestDeviceCode();
        await expectLater(
          auth(t.post, t.get).waitForSignIn(code),
          throwsA(
            isA<MicrosoftAuthException>()
                .having((e) => e.code, 'code', 'profile_not_found')
                .having((e) => e.message, 'message', contains('does not own')),
          ),
        );
      },
    );
  });

  group('refresh', () {
    test('renews the game token and keeps the old refresh token', () async {
      final happy = happyPath();
      final t = transport((url, body) async {
        if (url.path.endsWith('/token')) {
          // A refresh response without a new refresh token is normal.
          return json({'access_token': 'msa-2', 'expires_in': 3600});
        }
        return happy(url, body);
      });
      final session = await auth(t.post, t.get).refresh('refresh-old');

      expect(session.accessToken, 'mc-token');
      expect(session.refreshToken, 'refresh-old');
      expect(t.calls.first, 'POST /consumers/oauth2/v2.0/token');
      expect(t.calls, isNot(contains('GET /common/oauth2/v2.0/devicecode')));
    });

    test('an expired refresh token asks for a new sign-in', () async {
      final t = transport(
        (url, body) async => json({'error': 'invalid_grant'}, 400),
      );
      await expectLater(
        auth(t.post, t.get).refresh('stale'),
        throwsA(
          isA<MicrosoftAuthException>()
              .having((e) => e.code, 'code', 'invalid_grant')
              .having((e) => e.message, 'message', contains('Sign in again')),
        ),
      );
    });
  });
}
