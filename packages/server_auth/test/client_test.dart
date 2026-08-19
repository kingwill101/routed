import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('credentials sign-in handles CSRF and session cookies', () async {
    final requests = <http.BaseRequest>[];
    final client = AuthClient(
      baseUrl: Uri.parse('https://example.test/api'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/auth/csrf') {
          return http.Response(
            jsonEncode({'csrfToken': 'csrf-123'}),
            200,
            headers: {
              'content-type': 'application/json',
              'set-cookie': 'session_id=session-123; Path=/; HttpOnly',
            },
          );
        }
        expect(request.url.path, '/api/auth/signin/credentials');
        expect(request.headers['cookie'], 'session_id=session-123');
        expect(request.headers['x-csrf-token'], 'csrf-123');
        final body = jsonDecode(request.body);
        expect(body, {
          'email': 'ada@example.com',
          'password': 'correct horse battery staple',
          '_csrf': 'csrf-123',
        });
        return http.Response(
          jsonEncode({
            'user': {
              'id': 'user-1',
              'email': 'ada@example.com',
              'name': 'Ada',
              'roles': ['member'],
              'attributes': {},
            },
            'expires': '2030-01-01T00:00:00.000Z',
            'strategy': 'session',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final session = await client.signInWithCredentials(
      email: 'ada@example.com',
      password: 'correct horse battery staple',
    );

    expect(session.user.id, 'user-1');
    expect(session.user.email, 'ada@example.com');
    expect(session.strategy, AuthSessionStrategy.session);
    expect(requests.map((request) => request.url.path), [
      '/api/auth/csrf',
      '/api/auth/signin/credentials',
    ]);
  });

  test('provider metadata and signed-out sessions are typed', () async {
    final client = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/providers') {
          return http.Response(
            jsonEncode({
              'providers': [
                {
                  'id': 'credentials',
                  'name': 'Password',
                  'type': 'credentials',
                },
                {'id': 'github', 'name': 'GitHub', 'type': 'oauth'},
              ],
            }),
            200,
          );
        }
        expect(request.url.path, '/auth/session');
        return http.Response('null', 200);
      }),
    );

    final providers = await client.getProviders();
    final session = await client.getSession();

    expect(providers.map((provider) => provider.id), ['credentials', 'github']);
    expect(providers.last.type, 'oauth');
    expect(session, isNull);
  });

  test(
    'OAuth start returns the server redirect without following it',
    () async {
      final client = AuthClient(
        baseUrl: Uri.parse('https://example.test'),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/auth/signin/github');
          expect(request.url.queryParameters['callbackUrl'], 'app://callback');
          expect(request.followRedirects, isFalse);
          return http.Response(
            '',
            302,
            headers: {
              'location': 'https://github.test/oauth/authorize?state=state-1',
            },
          );
        }),
      );

      final redirect = await client.beginOAuth(
        provider: 'github',
        callbackUrl: 'app://callback',
      );

      expect(redirect.host, 'github.test');
      expect(redirect.queryParameters['state'], 'state-1');
    },
  );

  test('auth failures preserve sanitized code and retry information', () async {
    final client = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({'error': 'invalid_credentials'}),
          401,
          headers: {'retry-after': '9'},
        ),
      ),
    );

    expect(
      () => client.getSession(),
      throwsA(
        isA<AuthClientException>()
            .having((error) => error.statusCode, 'status', 401)
            .having((error) => error.code, 'code', 'invalid_credentials')
            .having(
              (error) => error.retryAfter,
              'retry-after',
              const Duration(seconds: 9),
            ),
      ),
    );
  });

  test('in-memory cookie store removes expired auth cookies', () {
    final store = InMemoryAuthClientCookieStore();
    store.save(const AuthClientCookie(name: 'session', value: 'secret'));
    store.save(
      AuthClientCookie(name: 'session', value: '', expires: DateTime.utc(1970)),
    );

    expect(store.load(), isEmpty);
  });

  test('in-memory cookie store removes cookies with negative Max-Age', () {
    final store = InMemoryAuthClientCookieStore();
    store.save(const AuthClientCookie(name: 'session', value: 'secret'));
    store.save(AuthClientCookie.fromSetCookie('session=; Max-Age=-1; Path=/'));

    expect(store.load(), isEmpty);
  });

  test('AuthClient honors Secure cookies by request scheme', () async {
    final secureCookie = AuthClientCookie.fromSetCookie(
      'session=secret; Secure; HttpOnly; Path=/',
    );
    expect(secureCookie.secure, isTrue);

    final store = InMemoryAuthClientCookieStore()..save(secureCookie);
    final requests = <http.BaseRequest>[];
    final httpClient = MockClient((request) async {
      requests.add(request);
      return http.Response('null', 200);
    });

    final cleartextClient = AuthClient(
      baseUrl: Uri.parse('http://example.test'),
      httpClient: httpClient,
      cookieStore: store,
    );
    await cleartextClient.getSession();
    expect(requests.single.headers['cookie'], isNull);

    final tlsClient = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      httpClient: httpClient,
      cookieStore: store,
    );
    await tlsClient.getSession();
    expect(requests[1].headers['cookie'], equals('session=secret'));
  });

  test(
    'changePassword sends reauthentication data and clears CSRF cache',
    () async {
      var csrfRequests = 0;
      var changeRequests = 0;
      final client = AuthClient(
        baseUrl: Uri.parse('https://example.test'),
        httpClient: MockClient((request) async {
          if (request.url.path == '/auth/csrf') {
            csrfRequests += 1;
            return http.Response(
              jsonEncode({'csrfToken': 'csrf-$csrfRequests'}),
              200,
              headers: {'set-cookie': 'session=session-$csrfRequests; Path=/'},
            );
          }
          changeRequests += 1;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(request.url.path, '/auth/password/change');
          expect(body, {
            'identifier': 'user@example.com',
            'currentPassword': changeRequests == 1
                ? 'old-password-123'
                : 'new-password-456',
            'newPassword': changeRequests == 1
                ? 'new-password-456'
                : 'third-password-789',
            '_csrf': 'csrf-$csrfRequests',
          });
          return http.Response('{}', 200);
        }),
      );

      await client.changePassword(
        identifier: 'user@example.com',
        currentPassword: 'old-password-123',
        newPassword: 'new-password-456',
      );
      await client.changePassword(
        identifier: 'user@example.com',
        currentPassword: 'new-password-456',
        newPassword: 'third-password-789',
      );

      expect(changeRequests, 2);
      expect(csrfRequests, 2);
    },
  );

  test('session helpers parse metadata and send revocation requests', () async {
    var csrfRequests = 0;
    final client = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/csrf') {
          csrfRequests += 1;
          return http.Response(
            jsonEncode({'csrfToken': 'csrf-$csrfRequests'}),
            200,
            headers: {'set-cookie': 'session=session-$csrfRequests; Path=/'},
          );
        }
        if (request.url.path == '/auth/sessions' && request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'sessions': [
                {
                  'id': 'session-1',
                  'userId': 'user-1',
                  'createdAt': '2030-01-01T00:00:00Z',
                  'expiresAt': '2030-02-01T00:00:00Z',
                  'lastUsedAt': '2030-01-01T01:00:00Z',
                  'revokedAt': null,
                  'ipAddress': '192.0.2.1',
                  'userAgent': 'test-agent',
                  'authenticationMethod': 'credentials',
                  'isCurrent': true,
                  'active': true,
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path == '/auth/sessions/revoke-others') {
          return http.Response(jsonEncode({'revoked': 2}), 200);
        }
        expect(request.url.path, '/auth/sessions/revoke');
        expect(jsonDecode(request.body), {
          'sessionId': 'session-1',
          '_csrf': 'csrf-$csrfRequests',
        });
        return http.Response('{}', 200);
      }),
    );

    final sessions = await client.getSessions();
    final revoked = await client.revokeOtherSessions();
    await client.revokeSession('session-1');

    expect(sessions.single.isCurrent, isTrue);
    expect(sessions.single.userAgent, 'test-agent');
    expect(revoked, 2);
  });

  test('two-factor helpers parse enrollment and send typed actions', () async {
    var csrfRequests = 0;
    final client = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/csrf') {
          csrfRequests += 1;
          return http.Response(
            jsonEncode({'csrfToken': 'csrf-$csrfRequests'}),
            200,
            headers: {'set-cookie': 'session=session-$csrfRequests; Path=/'},
          );
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['_csrf'], equals('csrf-1'));
        switch (request.url.path) {
          case '/auth/2fa/enroll':
            expect(body['accountLabel'], equals('ada@example.com'));
            return http.Response(
              jsonEncode({
                'secret': 'JBSWY3DPEHPK3PXP',
                'otpauthUri':
                    'otpauth://totp/server_auth:ada@example.com?secret=JBSWY3DPEHPK3PXP',
                'expiresAt': '2030-01-01T00:10:00Z',
              }),
              200,
            );
          case '/auth/2fa/enroll/verify':
            expect(body['code'], equals('123456'));
            return http.Response(
              jsonEncode({
                'recoveryCodes': ['ABCD-EFGH-IJKL'],
              }),
              200,
            );
          case '/auth/2fa/verify':
            expect(body['code'], equals('123456'));
            return http.Response('{}', 200);
          default:
            throw StateError('unexpected auth client route');
        }
      }),
    );

    final enrollment = await client.beginTwoFactorEnrollment(
      accountLabel: 'ada@example.com',
    );
    final recovery = await client.verifyTwoFactorEnrollment(code: '123456');
    await client.verifyTwoFactor(code: '123456');

    expect(enrollment.otpauthUri.scheme, equals('otpauth'));
    expect(recovery.codes, equals(['ABCD-EFGH-IJKL']));
    expect(csrfRequests, equals(1));
  });

  test('credentials sign-in surfaces and completes a TOTP challenge', () async {
    final client = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/csrf') {
          return http.Response(
            jsonEncode({'csrfToken': 'csrf-1'}),
            200,
            headers: {'set-cookie': 'session=session-1; Path=/'},
          );
        }
        if (request.url.path == '/auth/signin/credentials') {
          return http.Response(
            jsonEncode({
              'status': 'two_factor_required',
              'challengeToken': 'challenge-1',
              'expiresAt': '2030-01-01T00:05:00Z',
            }),
            202,
          );
        }
        expect(request.url.path, '/auth/2fa/challenge/verify');
        expect(jsonDecode(request.body), {
          'challengeToken': 'challenge-1',
          'code': '123456',
          'trustDevice': true,
          '_csrf': 'csrf-1',
        });
        return http.Response(
          jsonEncode({
            'user': {
              'id': 'user-1',
              'email': 'ada@example.com',
              'roles': [],
              'attributes': {},
            },
            'expires': '2030-01-01T01:00:00Z',
            'strategy': 'session',
          }),
          200,
        );
      }),
    );

    AuthClientTwoFactorRequiredException? required;
    try {
      await client.signInWithCredentials(
        email: 'ada@example.com',
        password: 'correct horse battery staple',
      );
    } on AuthClientTwoFactorRequiredException catch (error) {
      required = error;
    }
    expect(required, isNotNull);
    final session = await client.verifyTwoFactorChallenge(
      challengeToken: required!.challengeToken,
      code: '123456',
      trustDevice: true,
    );
    expect(session.user.id, equals('user-1'));
  });

  test('completes a pending sign-in with a recovery code', () async {
    final client = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/csrf') {
          return http.Response(
            jsonEncode({'csrfToken': 'csrf-1'}),
            200,
            headers: {'set-cookie': 'session=session-1; Path=/'},
          );
        }
        if (request.url.path == '/auth/signin/credentials') {
          return http.Response(
            jsonEncode({
              'status': 'two_factor_required',
              'challengeToken': 'challenge-1',
              'expiresAt': '2030-01-01T00:05:00Z',
            }),
            202,
          );
        }
        expect(request.url.path, '/auth/2fa/challenge/recovery-code');
        expect(jsonDecode(request.body), {
          'challengeToken': 'challenge-1',
          'recoveryCode': 'ABCD-EFGH',
          '_csrf': 'csrf-1',
        });
        return http.Response(
          jsonEncode({
            'user': {
              'id': 'user-1',
              'email': 'ada@example.com',
              'roles': [],
              'attributes': {},
            },
            'expires': '2030-01-01T01:00:00Z',
            'strategy': 'session',
          }),
          200,
        );
      }),
    );

    AuthClientTwoFactorRequiredException? required;
    try {
      await client.signInWithCredentials(
        email: 'ada@example.com',
        password: 'correct horse battery staple',
      );
    } on AuthClientTwoFactorRequiredException catch (error) {
      required = error;
    }
    expect(required, isNotNull);
    final session = await client.verifyTwoFactorRecoveryChallenge(
      challengeToken: required!.challengeToken,
      recoveryCode: 'ABCD-EFGH',
    );
    expect(session.user.id, equals('user-1'));
  });

  test('verifies and revokes a two-factor step-up proof', () async {
    final client = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/csrf') {
          return http.Response(
            jsonEncode({'csrfToken': 'csrf-1'}),
            200,
            headers: {'set-cookie': 'session=session-1; Path=/'},
          );
        }
        if (request.url.path == '/auth/2fa/step-up') {
          expect(jsonDecode(request.body), {
            'code': '123456',
            '_csrf': 'csrf-1',
          });
          return http.Response(
            jsonEncode({'verified': true, 'expiresAt': '2030-01-01T00:05:00Z'}),
            200,
            headers: {
              'set-cookie': 'two_factor_step_up=proof-1; Path=/; HttpOnly',
            },
          );
        }
        expect(request.url.path, '/auth/2fa/step-up/revoke');
        expect(jsonDecode(request.body), {'_csrf': 'csrf-1'});
        return http.Response(jsonEncode({'status': 'step_up_revoked'}), 200);
      }),
    );

    final proof = await client.verifyTwoFactorStepUp(code: '123456');
    expect(proof.expiresAt, equals(DateTime.utc(2030, 1, 1, 0, 5)));
    await client.revokeTwoFactorStepUp();
  });
}
