import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('credentials sign-in handles CSRF and session cookies', () async {
    final requests = <http.BaseRequest>[];
    final plugin = const AuthCredentialsClientPlugin();
    final auth = AuthClient(
      baseUrl: Uri.parse('https://example.test/api'),
      plugins: [plugin],
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
    final client = auth.plugins.use(plugin);

    final session = await client.signIn(
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
    final providerPlugin = const AuthProviderClientPlugin();
    final sessionPlugin = const AuthSessionClientPlugin();
    final auth = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      plugins: [providerPlugin, sessionPlugin],
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
    final providersClient = auth.plugins.use(providerPlugin);
    final sessionsClient = auth.plugins.use(sessionPlugin);

    final providers = await providersClient.list();
    final session = await sessionsClient.current();

    expect(providers.map((provider) => provider.id), ['credentials', 'github']);
    expect(providers.last.type, 'oauth');
    expect(session, isNull);
  });

  test(
    'OAuth start returns the server redirect without following it',
    () async {
      final plugin = const AuthOAuthClientPlugin();
      final auth = AuthClient(
        baseUrl: Uri.parse('https://example.test'),
        plugins: [plugin],
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
      final client = auth.plugins.use(plugin);

      final redirect = await client.begin(
        provider: 'github',
        callbackUrl: 'app://callback',
      );

      expect(redirect.host, 'github.test');
      expect(redirect.queryParameters['state'], 'state-1');
    },
  );

  test('auth failures preserve sanitized code and retry information', () async {
    final plugin = const AuthSessionClientPlugin();
    final auth = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      plugins: [plugin],
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({'error': 'invalid_credentials'}),
          401,
          headers: {'retry-after': '9'},
        ),
      ),
    );
    final client = auth.plugins.use(plugin);

    expect(
      () => client.current(),
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

  test('cookie Max-Age becomes an absolute expiry deadline', () {
    final receivedAt = DateTime.utc(2030, 1, 1);
    final cookie = AuthClientCookie.fromSetCookie(
      'session=secret; Max-Age=60; Path=/',
      now: receivedAt,
    );

    expect(cookie.maxAge, 60);
    expect(cookie.expires, receivedAt.add(const Duration(minutes: 1)));
  });

  test('transport excludes expired cookies from requests', () async {
    final cookieStore = _FixedCookieStore([
      AuthClientCookie(
        name: 'expired',
        value: 'secret',
        expires: DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
      ),
      const AuthClientCookie(name: 'active', value: 'current'),
    ]);
    final transport = AuthClientTransport(
      baseUrl: Uri.parse('https://example.test'),
      cookieStore: cookieStore,
      httpClient: MockClient((request) async {
        expect(request.headers['cookie'], 'active=current');
        return http.Response(jsonEncode({'providers': <Object?>[]}), 200);
      }),
    );

    await transport.request('GET', const AuthRoutePath('/providers'));
  });

  test('transport honors Secure cookies by request scheme', () async {
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

    final cleartextTransport = AuthClientTransport(
      baseUrl: Uri.parse('http://example.test'),
      httpClient: httpClient,
      cookieStore: store,
    );
    await cleartextTransport.request('GET', const AuthRoutePath('/session'));
    expect(requests.single.headers['cookie'], isNull);

    final tlsTransport = AuthClientTransport(
      baseUrl: Uri.parse('https://example.test'),
      httpClient: httpClient,
      cookieStore: store,
    );
    await tlsTransport.request('GET', const AuthRoutePath('/session'));
    expect(requests[1].headers['cookie'], equals('session=secret'));
  });

  test('invalid CSRF refreshes once and retries the mutation', () async {
    var csrfRequests = 0;
    var mutationRequests = 0;
    final transport = AuthClientTransport(
      baseUrl: Uri.parse('https://example.test'),
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/csrf') {
          csrfRequests += 1;
          expect(
            request.headers['cookie'],
            csrfRequests == 1 ? isNull : 'session=session-2',
          );
          return http.Response(
            jsonEncode({'csrfToken': 'csrf-$csrfRequests'}),
            200,
            headers: {'set-cookie': 'session=session-$csrfRequests; Path=/'},
          );
        }
        mutationRequests += 1;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['_csrf'], 'csrf-$mutationRequests');
        if (mutationRequests == 1) {
          return http.Response(
            jsonEncode({'error': 'invalid_csrf'}),
            403,
            headers: {'set-cookie': 'session=session-2; Path=/'},
          );
        }
        return http.Response('{}', 200);
      }),
    );

    await transport.mutate('POST', const AuthRoutePath('/sessions/revoke'), {
      'sessionId': 'session-1',
    });

    expect(csrfRequests, 2);
    expect(mutationRequests, 2);
  });

  test(
    'password plugin sends reauthentication data and clears CSRF cache',
    () async {
      var csrfRequests = 0;
      var changeRequests = 0;
      final plugin = const AuthPasswordClientPlugin();
      final auth = AuthClient(
        baseUrl: Uri.parse('https://example.test'),
        plugins: [plugin],
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
      final client = auth.plugins.use(plugin);

      await client.change(
        identifier: 'user@example.com',
        currentPassword: 'old-password-123',
        newPassword: 'new-password-456',
      );
      await client.change(
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
    final plugin = const AuthSessionClientPlugin();
    final auth = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      plugins: [plugin],
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
    final client = auth.plugins.use(plugin);

    final sessions = await client.list();
    final revoked = await client.revokeOthers();
    await client.revoke('session-1');

    expect(sessions.single.isCurrent, isTrue);
    expect(sessions.single.userAgent, 'test-agent');
    expect(revoked, 2);
  });

  test('two-factor helpers parse enrollment and send typed actions', () async {
    var csrfRequests = 0;
    final plugin = const AuthTwoFactorClientPlugin();
    final auth = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      plugins: [plugin],
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
    final client = auth.plugins.use(plugin);

    final enrollment = await client.beginEnrollment(
      accountLabel: 'ada@example.com',
    );
    final recovery = await client.verifyEnrollment(code: '123456');
    await client.verify(code: '123456');

    expect(enrollment.otpauthUri.scheme, equals('otpauth'));
    expect(recovery.codes, equals(['ABCD-EFGH-IJKL']));
    expect(csrfRequests, equals(1));
  });

  test('credentials sign-in surfaces and completes a TOTP challenge', () async {
    final credentialsPlugin = const AuthCredentialsClientPlugin();
    final twoFactorPlugin = const AuthTwoFactorClientPlugin();
    final auth = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      plugins: [credentialsPlugin, twoFactorPlugin],
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
    final credentials = auth.plugins.use(credentialsPlugin);
    final twoFactor = auth.plugins.use(twoFactorPlugin);

    AuthClientTwoFactorRequiredException? required;
    try {
      await credentials.signIn(
        email: 'ada@example.com',
        password: 'correct horse battery staple',
      );
    } on AuthClientTwoFactorRequiredException catch (error) {
      required = error;
    }
    expect(required, isNotNull);
    final session = await twoFactor.verifyChallenge(
      challengeToken: required!.challengeToken,
      code: '123456',
      trustDevice: true,
    );
    expect(session.user.id, equals('user-1'));
  });

  test('completes a pending sign-in with a recovery code', () async {
    final credentialsPlugin = const AuthCredentialsClientPlugin();
    final twoFactorPlugin = const AuthTwoFactorClientPlugin();
    final auth = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      plugins: [credentialsPlugin, twoFactorPlugin],
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
    final credentials = auth.plugins.use(credentialsPlugin);
    final twoFactor = auth.plugins.use(twoFactorPlugin);

    AuthClientTwoFactorRequiredException? required;
    try {
      await credentials.signIn(
        email: 'ada@example.com',
        password: 'correct horse battery staple',
      );
    } on AuthClientTwoFactorRequiredException catch (error) {
      required = error;
    }
    expect(required, isNotNull);
    final session = await twoFactor.verifyRecoveryChallenge(
      challengeToken: required!.challengeToken,
      recoveryCode: 'ABCD-EFGH',
    );
    expect(session.user.id, equals('user-1'));
  });

  test('verifies and revokes a two-factor step-up proof', () async {
    final plugin = const AuthTwoFactorClientPlugin();
    final auth = AuthClient(
      baseUrl: Uri.parse('https://example.test'),
      plugins: [plugin],
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
    final client = auth.plugins.use(plugin);

    final proof = await client.verifyStepUp(code: '123456');
    expect(proof.expiresAt, equals(DateTime.utc(2030, 1, 1, 0, 5)));
    await client.revokeStepUp();
  });
}

final class _FixedCookieStore implements AuthClientCookieStore {
  _FixedCookieStore(this.cookies);

  final List<AuthClientCookie> cookies;

  @override
  Iterable<AuthClientCookie> load() => cookies;

  @override
  void save(AuthClientCookie cookie) {}
}
