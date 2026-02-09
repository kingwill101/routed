import 'dart:convert';
import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed/session.dart';
import 'package:routed/src/sessions/middleware.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

import '../test_engine.dart';

/// Builds an engine with session middleware but WITHOUT AuthServiceProvider
/// or AuthManager — simulating a minimal setup where only SessionAuth is
/// available.
Engine _minimalSessionEngine({void Function(Engine engine)? configure}) {
  final sessionConfig = _sessionConfig();
  final engine = testEngine(
    config: EngineConfig(
      security: const EngineSecurityFeatures(csrfProtection: false),
    ),
    options: [withSessionConfig(sessionConfig)],
  );
  engine.addGlobalMiddleware(sessionMiddleware());
  engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());
  configure?.call(engine);
  return engine;
}

SessionConfig _sessionConfig() {
  final key = base64.encode(List<int>.generate(32, (i) => i + 1));
  return SessionConfig.cookie(
    appKey: 'base64:$key',
    cookieName: 'test_session',
    options: Options(
      path: '/',
      secure: false,
      httpOnly: true,
      sameSite: SameSite.lax,
    ),
  );
}

Engine _authEngine(
  AuthManager manager, {
  void Function(Engine engine)? configure,
}) {
  final sessionConfig = _sessionConfig();
  final engine = testEngine(
    config: EngineConfig(
      security: const EngineSecurityFeatures(csrfProtection: false),
    ),
    options: [withSessionConfig(sessionConfig)],
  );
  engine.addGlobalMiddleware(sessionMiddleware());
  engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());
  // Wire the static callback so SessionAuth.updateSession delegates to this
  // manager instance (mirrors what AuthServiceProvider does in a real app).
  SessionAuth.setSessionUpdater(manager.updateSession);
  AuthRoutes(manager).register(engine.defaultRouter);
  configure?.call(engine);
  return engine;
}

String _cookieHeader(Cookie cookie) => '${cookie.name}=${cookie.value}';

Map<String, dynamic>? _decodeJson(TestResponse response) {
  final body = response.body.trim();
  if (body.isEmpty) return null;
  final decoded = jsonDecode(body);
  if (decoded is Map<String, dynamic>) return decoded;
  return null;
}

AuthManager _sessionManager({AuthCallbacks? callbacks}) {
  return AuthManager(
    AuthOptions(
      providers: [
        CredentialsProvider(
          authorize: (ctx, provider, credentials) async {
            if (credentials.password == 'secret') {
              return AuthUser(
                id: 'user-1',
                email: credentials.email,
                name: 'Test User',
                roles: const ['member'],
                attributes: const {'theme': 'light'},
              );
            }
            return null;
          },
        ),
      ],
      sessionStrategy: AuthSessionStrategy.session,
      enforceCsrf: false,
      callbacks: callbacks ?? const AuthCallbacks(),
    ),
  );
}

const String _jwtSecret = 'test-jwt-secret-for-update-session';

AuthManager _jwtManager({AuthCallbacks? callbacks}) {
  return AuthManager(
    AuthOptions(
      providers: [
        CredentialsProvider(
          authorize: (ctx, provider, credentials) async {
            if (credentials.password == 'secret') {
              return AuthUser(
                id: 'user-1',
                email: credentials.email,
                name: 'Test User',
                roles: const ['member'],
                attributes: const {'theme': 'light'},
              );
            }
            return null;
          },
        ),
      ],
      sessionStrategy: AuthSessionStrategy.jwt,
      jwtOptions: const JwtSessionOptions(secret: _jwtSecret),
      enforceCsrf: false,
      callbacks: callbacks ?? const AuthCallbacks(),
    ),
  );
}

/// Signs in via credentials and returns the session cookie for subsequent
/// requests.
Future<Cookie> _signIn(TestClient client) async {
  final csrfResponse = await client.get('/auth/csrf');
  csrfResponse.assertStatus(HttpStatus.ok);
  final sessionCookie = csrfResponse.cookie('test_session');
  expect(sessionCookie, isNotNull);

  final signInResponse = await client.postJson(
    '/auth/signin/credentials',
    {'email': 'user@example.com', 'password': 'secret'},
    headers: {
      HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
    },
  );
  signInResponse.assertStatus(HttpStatus.ok);

  final authCookie = signInResponse.cookie('test_session');
  expect(authCookie, isNotNull);
  return authCookie!;
}

void main() {
  _sessionAuthUpdateSessionTests();

  group('AuthManager.updateSession', () {
    group('session strategy', () {
      test('updates principal attributes in the session', () async {
        final manager = _sessionManager();
        final engine = _authEngine(
          manager,
          configure: (engine) {
            engine.post('/update-profile', (ctx) async {
              final updated = AuthPrincipal(
                id: 'user-1',
                roles: const ['member', 'admin'],
                attributes: const {
                  'email': 'user@example.com',
                  'name': 'Updated User',
                  'theme': 'dark',
                },
              );
              final session = await manager.updateSession(ctx, updated);
              return ctx.json({
                'user': session.user.toJson(),
                'strategy': session.strategy?.name,
              });
            });
          },
        );

        await engine.initialize();
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(() async => await client.close());

        final authCookie = await _signIn(client);

        // Verify initial session state.
        final sessionBefore = await client.get(
          '/auth/session',
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(authCookie)],
          },
        );
        sessionBefore.assertStatus(HttpStatus.ok);
        final beforeBody = _decodeJson(sessionBefore)!;
        expect(beforeBody['user']['name'], equals('Test User'));
        expect(beforeBody['user']['roles'], equals(['member']));

        final updatedSessionCookie =
            sessionBefore.cookie('test_session') ?? authCookie;

        // Call the update endpoint.
        final updateResponse = await client.postJson(
          '/update-profile',
          <String, dynamic>{},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(updatedSessionCookie)],
          },
        );
        updateResponse.assertStatus(HttpStatus.ok);
        final updateBody = _decodeJson(updateResponse)!;
        expect(updateBody['strategy'], equals('session'));
        expect(updateBody['user']['name'], equals('Updated User'));
        expect(updateBody['user']['roles'], contains('admin'));

        // Verify session reflects the update on subsequent requests.
        final afterCookie =
            updateResponse.cookie('test_session') ?? updatedSessionCookie;
        final sessionAfter = await client.get(
          '/auth/session',
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(afterCookie)],
          },
        );
        sessionAfter.assertStatus(HttpStatus.ok);
        final afterBody = _decodeJson(sessionAfter)!;
        expect(afterBody['user']['name'], equals('Updated User'));
        expect(afterBody['user']['roles'], contains('admin'));
      });

      test('returns AuthSession with session strategy', () async {
        final manager = _sessionManager();
        AuthSession? capturedSession;
        final engine = _authEngine(
          manager,
          configure: (engine) {
            engine.post('/update', (ctx) async {
              final updated = AuthPrincipal(
                id: 'user-1',
                roles: const ['editor'],
                attributes: const {'email': 'user@example.com'},
              );
              capturedSession = await manager.updateSession(ctx, updated);
              return ctx.json({'ok': true});
            });
          },
        );

        await engine.initialize();
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(() async => await client.close());

        final authCookie = await _signIn(client);
        final afterCookie =
            (await client.get(
              '/auth/session',
              headers: {
                HttpHeaders.cookieHeader: [_cookieHeader(authCookie)],
              },
            )).cookie('test_session') ??
            authCookie;

        await client.postJson(
          '/update',
          <String, dynamic>{},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(afterCookie)],
          },
        );

        expect(capturedSession, isNotNull);
        expect(capturedSession!.strategy, equals(AuthSessionStrategy.session));
        expect(capturedSession!.user.id, equals('user-1'));
        expect(capturedSession!.user.roles, equals(['editor']));
      });

      test('preserves session max age configuration', () async {
        final manager = AuthManager(
          AuthOptions(
            providers: [
              CredentialsProvider(
                authorize: (ctx, provider, credentials) async {
                  return AuthUser(id: 'user-1', email: 'user@example.com');
                },
              ),
            ],
            sessionStrategy: AuthSessionStrategy.session,
            sessionMaxAge: const Duration(hours: 2),
            enforceCsrf: false,
          ),
        );

        AuthSession? capturedSession;
        final engine = _authEngine(
          manager,
          configure: (engine) {
            engine.post('/update', (ctx) async {
              final updated = AuthPrincipal(
                id: 'user-1',
                roles: const ['member'],
                attributes: const {'email': 'user@example.com'},
              );
              capturedSession = await manager.updateSession(ctx, updated);
              return ctx.json({'ok': true});
            });
          },
        );

        await engine.initialize();
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(() async => await client.close());

        final authCookie = await _signIn(client);
        final afterCookie =
            (await client.get(
              '/auth/session',
              headers: {
                HttpHeaders.cookieHeader: [_cookieHeader(authCookie)],
              },
            )).cookie('test_session') ??
            authCookie;

        await client.postJson(
          '/update',
          <String, dynamic>{},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(afterCookie)],
          },
        );

        expect(capturedSession, isNotNull);
        expect(capturedSession!.expiresAt, isNotNull);
        // The expiry should be roughly 2 hours from now.
        final diff = capturedSession!.expiresAt!
            .difference(DateTime.now())
            .inMinutes;
        expect(diff, greaterThan(110));
        expect(diff, lessThanOrEqualTo(120));
      });
    });

    group('JWT strategy', () {
      test('reissues JWT cookie with updated claims', () async {
        final manager = _jwtManager();
        final engine = _authEngine(
          manager,
          configure: (engine) {
            engine.post('/update-profile', (ctx) async {
              final session = await manager.updateSession(
                ctx,
                AuthPrincipal(
                  id: 'user-1',
                  roles: const ['member', 'admin'],
                  attributes: const {
                    'email': 'user@example.com',
                    'name': 'Updated JWT User',
                    'theme': 'dark',
                  },
                ),
              );
              return ctx.json({
                'user': session.user.toJson(),
                'strategy': session.strategy?.name,
                'hasToken': session.token != null && session.token!.isNotEmpty,
              });
            });
          },
        );

        await engine.initialize();
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(() async => await client.close());

        final authCookie = await _signIn(client);

        // Read initial session.
        final sessionBefore = await client.get(
          '/auth/session',
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(authCookie)],
          },
        );
        sessionBefore.assertStatus(HttpStatus.ok);
        final beforeBody = _decodeJson(sessionBefore)!;
        expect(beforeBody['user']['name'], equals('Test User'));

        final jwtCookie =
            sessionBefore.cookie('routed_auth_token') ?? authCookie;

        // Call update.
        final updateResponse = await client.postJson(
          '/update-profile',
          <String, dynamic>{},
          headers: {
            HttpHeaders.cookieHeader: [
              _cookieHeader(authCookie),
              if (jwtCookie != authCookie) _cookieHeader(jwtCookie),
            ],
          },
        );
        updateResponse.assertStatus(HttpStatus.ok);
        final updateBody = _decodeJson(updateResponse)!;
        expect(updateBody['strategy'], equals('jwt'));
        expect(updateBody['user']['name'], equals('Updated JWT User'));
        expect(updateBody['user']['roles'], contains('admin'));
        expect(updateBody['hasToken'], isTrue);

        // The response should set a new JWT cookie.
        final newJwtCookie = updateResponse.cookie('routed_auth_token');
        expect(
          newJwtCookie,
          isNotNull,
          reason: 'updateSession should attach a new JWT cookie',
        );
      });

      test('returns AuthSession with JWT strategy and token', () async {
        final manager = _jwtManager();
        AuthSession? capturedSession;
        final engine = _authEngine(
          manager,
          configure: (engine) {
            engine.post('/update', (ctx) async {
              capturedSession = await manager.updateSession(
                ctx,
                AuthPrincipal(
                  id: 'user-1',
                  roles: const ['viewer'],
                  attributes: const {'email': 'user@example.com'},
                ),
              );
              return ctx.json({'ok': true});
            });
          },
        );

        await engine.initialize();
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(() async => await client.close());

        final authCookie = await _signIn(client);

        await client.postJson(
          '/update',
          <String, dynamic>{},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(authCookie)],
          },
        );

        expect(capturedSession, isNotNull);
        expect(capturedSession!.strategy, equals(AuthSessionStrategy.jwt));
        expect(capturedSession!.user.id, equals('user-1'));
        expect(capturedSession!.user.roles, equals(['viewer']));
        expect(capturedSession!.token, isNotNull);
        expect(capturedSession!.token, isNotEmpty);
        expect(capturedSession!.expiresAt, isNotNull);
      });

      test('invokes JWT callback during updateSession', () async {
        final jwtCallbackInvocations = <Map<String, dynamic>>[];
        final manager = _jwtManager(
          callbacks: AuthCallbacks(
            jwt: (context) async {
              jwtCallbackInvocations.add(
                Map<String, dynamic>.from(context.token),
              );
              return {
                ...context.token,
                'custom_claim': 'injected_by_callback',
                'role_override': 'superadmin',
              };
            },
          ),
        );

        AuthSession? capturedSession;
        final engine = _authEngine(
          manager,
          configure: (engine) {
            engine.post('/update', (ctx) async {
              capturedSession = await manager.updateSession(
                ctx,
                AuthPrincipal(
                  id: 'user-1',
                  roles: const ['member'],
                  attributes: const {'email': 'user@example.com'},
                ),
              );
              return ctx.json({'ok': true});
            });
          },
        );

        await engine.initialize();
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(() async => await client.close());

        final authCookie = await _signIn(client);

        // The sign-in itself invokes JWT callback once.
        final signInCallCount = jwtCallbackInvocations.length;

        await client.postJson(
          '/update',
          <String, dynamic>{},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(authCookie)],
          },
        );

        // updateSession should have invoked the callback again.
        expect(jwtCallbackInvocations.length, equals(signInCallCount + 1));
        final lastInvocation = jwtCallbackInvocations.last;
        expect(lastInvocation['sub'], equals('user-1'));
        expect(lastInvocation['email'], equals('user@example.com'));

        // Verify the returned session has the token.
        expect(capturedSession, isNotNull);
        expect(capturedSession!.token, isNotNull);
        expect(capturedSession!.token, isNotEmpty);
      });

      test('throws AuthFlowException when JWT secret is empty', () async {
        final manager = AuthManager(
          AuthOptions(
            providers: [
              CredentialsProvider(
                authorize: (ctx, provider, credentials) async {
                  return AuthUser(id: 'user-1', email: 'user@example.com');
                },
              ),
            ],
            sessionStrategy: AuthSessionStrategy.jwt,
            jwtOptions: const JwtSessionOptions(secret: ''),
            enforceCsrf: false,
          ),
        );

        Object? caughtError;
        final engine = _authEngine(
          manager,
          configure: (engine) {
            engine.post('/update', (ctx) async {
              try {
                await manager.updateSession(
                  ctx,
                  AuthPrincipal(id: 'user-1', roles: const []),
                );
                return ctx.json({'ok': true});
              } on AuthFlowException catch (e) {
                caughtError = e;
                return ctx.json({
                  'error': e.code,
                }, statusCode: HttpStatus.internalServerError);
              }
            });
          },
        );

        await engine.initialize();
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(() async => await client.close());

        // Get a session cookie (sign-in will fail for JWT with empty secret,
        // so just get a csrf cookie to have a valid session).
        final csrfResponse = await client.get('/auth/csrf');
        final sessionCookie = csrfResponse.cookie('test_session')!;

        final response = await client.postJson(
          '/update',
          <String, dynamic>{},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
          },
        );

        expect(caughtError, isA<AuthFlowException>());
        expect(
          (caughtError as AuthFlowException).code,
          equals('missing_jwt_secret'),
        );
        final body = _decodeJson(response)!;
        expect(body['error'], equals('missing_jwt_secret'));
      });
    });

    group('round-trip verification', () {
      test(
        'session: updated attributes are visible via resolveSession',
        () async {
          final manager = _sessionManager();
          final engine = _authEngine(
            manager,
            configure: (engine) {
              engine.post('/update', (ctx) async {
                await manager.updateSession(
                  ctx,
                  AuthPrincipal(
                    id: 'user-1',
                    roles: const ['admin'],
                    attributes: const {
                      'email': 'updated@example.com',
                      'name': 'Admin User',
                      'department': 'engineering',
                    },
                  ),
                );
                return ctx.json({'ok': true});
              });
            },
          );

          await engine.initialize();
          final client = TestClient(RoutedRequestHandler(engine));
          addTearDown(() async => await client.close());

          final authCookie = await _signIn(client);

          // Read session cookie chain through the session resolve.
          final preCookie =
              (await client.get(
                '/auth/session',
                headers: {
                  HttpHeaders.cookieHeader: [_cookieHeader(authCookie)],
                },
              )).cookie('test_session') ??
              authCookie;

          final updateResponse = await client.postJson(
            '/update',
            <String, dynamic>{},
            headers: {
              HttpHeaders.cookieHeader: [_cookieHeader(preCookie)],
            },
          );
          final postCookie = updateResponse.cookie('test_session') ?? preCookie;

          final sessionResponse = await client.get(
            '/auth/session',
            headers: {
              HttpHeaders.cookieHeader: [_cookieHeader(postCookie)],
            },
          );
          sessionResponse.assertStatus(HttpStatus.ok);
          final sessionBody = _decodeJson(sessionResponse)!;
          expect(sessionBody['user']['email'], equals('updated@example.com'));
          expect(sessionBody['user']['name'], equals('Admin User'));
          expect(sessionBody['user']['roles'], contains('admin'));
        },
      );

      test('jwt: updated token is resolvable via resolveSession', () async {
        final manager = _jwtManager();
        final engine = _authEngine(
          manager,
          configure: (engine) {
            engine.post('/update', (ctx) async {
              await manager.updateSession(
                ctx,
                AuthPrincipal(
                  id: 'user-1',
                  roles: const ['admin', 'billing'],
                  attributes: const {
                    'email': 'admin@example.com',
                    'name': 'Admin User',
                  },
                ),
              );
              return ctx.json({'ok': true});
            });
          },
        );

        await engine.initialize();
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(() async => await client.close());

        final authCookie = await _signIn(client);

        final updateResponse = await client.postJson(
          '/update',
          <String, dynamic>{},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(authCookie)],
          },
        );

        // Collect all cookies from the update response to send back.
        final cookies = <String>[_cookieHeader(authCookie)];
        final newSession = updateResponse.cookie('test_session');
        if (newSession != null) cookies.add(_cookieHeader(newSession));
        final newJwt = updateResponse.cookie('routed_auth_token');
        if (newJwt != null) cookies.add(_cookieHeader(newJwt));

        final sessionResponse = await client.get(
          '/auth/session',
          headers: {HttpHeaders.cookieHeader: cookies},
        );
        sessionResponse.assertStatus(HttpStatus.ok);
        final sessionBody = _decodeJson(sessionResponse)!;
        expect(sessionBody['user']['name'], equals('Admin User'));
        expect(sessionBody['user']['email'], equals('admin@example.com'));
        expect(sessionBody['user']['roles'], contains('admin'));
        expect(sessionBody['user']['roles'], contains('billing'));
        expect(sessionBody['strategy'], equals('jwt'));
      });
    });

    group('edge cases', () {
      test('updateSession with empty roles clears roles', () async {
        final manager = _sessionManager();
        final engine = _authEngine(
          manager,
          configure: (engine) {
            engine.post('/update', (ctx) async {
              final session = await manager.updateSession(
                ctx,
                AuthPrincipal(
                  id: 'user-1',
                  roles: const [],
                  attributes: const {'email': 'user@example.com'},
                ),
              );
              return ctx.json({'roles': session.user.roles});
            });
          },
        );

        await engine.initialize();
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(() async => await client.close());

        final authCookie = await _signIn(client);
        final preCookie =
            (await client.get(
              '/auth/session',
              headers: {
                HttpHeaders.cookieHeader: [_cookieHeader(authCookie)],
              },
            )).cookie('test_session') ??
            authCookie;

        final response = await client.postJson(
          '/update',
          <String, dynamic>{},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(preCookie)],
          },
        );
        response.assertStatus(HttpStatus.ok);
        final body = _decodeJson(response)!;
        expect(body['roles'], isEmpty);
      });

      test('updateSession with changed id updates the user id', () async {
        final manager = _sessionManager();
        final engine = _authEngine(
          manager,
          configure: (engine) {
            engine.post('/update', (ctx) async {
              final session = await manager.updateSession(
                ctx,
                AuthPrincipal(
                  id: 'user-2',
                  roles: const ['member'],
                  attributes: const {'email': 'user2@example.com'},
                ),
              );
              return ctx.json({'id': session.user.id});
            });
          },
        );

        await engine.initialize();
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(() async => await client.close());

        final authCookie = await _signIn(client);
        final preCookie =
            (await client.get(
              '/auth/session',
              headers: {
                HttpHeaders.cookieHeader: [_cookieHeader(authCookie)],
              },
            )).cookie('test_session') ??
            authCookie;

        final response = await client.postJson(
          '/update',
          <String, dynamic>{},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(preCookie)],
          },
        );
        response.assertStatus(HttpStatus.ok);
        final body = _decodeJson(response)!;
        expect(body['id'], equals('user-2'));
      });

      test('multiple updateSession calls use last values', () async {
        final manager = _sessionManager();
        final engine = _authEngine(
          manager,
          configure: (engine) {
            engine.post('/update', (ctx) async {
              // First update.
              await manager.updateSession(
                ctx,
                AuthPrincipal(
                  id: 'user-1',
                  roles: const ['role-a'],
                  attributes: const {'email': 'a@example.com'},
                ),
              );
              // Second update overwrites the first.
              final session = await manager.updateSession(
                ctx,
                AuthPrincipal(
                  id: 'user-1',
                  roles: const ['role-b'],
                  attributes: const {'email': 'b@example.com', 'name': 'Final'},
                ),
              );
              return ctx.json({
                'roles': session.user.roles,
                'email': session.user.email,
                'name': session.user.name,
              });
            });
          },
        );

        await engine.initialize();
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(() async => await client.close());

        final authCookie = await _signIn(client);
        final preCookie =
            (await client.get(
              '/auth/session',
              headers: {
                HttpHeaders.cookieHeader: [_cookieHeader(authCookie)],
              },
            )).cookie('test_session') ??
            authCookie;

        final response = await client.postJson(
          '/update',
          <String, dynamic>{},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(preCookie)],
          },
        );
        response.assertStatus(HttpStatus.ok);
        final body = _decodeJson(response)!;
        expect(body['roles'], equals(['role-b']));
        expect(body['email'], equals('b@example.com'));
        expect(body['name'], equals('Final'));
      });
    });
  });
}

void _sessionAuthUpdateSessionTests() {
  group('SessionAuth.updateSession', () {
    group('with AuthManager (delegates to AuthSessionUpdater)', () {
      test(
        'session strategy: updates principal via SessionAuth facade',
        () async {
          final manager = _sessionManager();
          final engine = _authEngine(
            manager,
            configure: (engine) {
              engine.post('/update', (ctx) async {
                final updated = AuthPrincipal(
                  id: 'user-1',
                  roles: const ['admin'],
                  attributes: const {
                    'email': 'user@example.com',
                    'name': 'SessionAuth Updated',
                    'theme': 'dark',
                  },
                );
                // Use the convenience method — no container lookup.
                await SessionAuth.updateSession(ctx, updated);
                return ctx.json({'ok': true});
              });
            },
          );

          await engine.initialize();
          final client = TestClient(RoutedRequestHandler(engine));
          addTearDown(() async => await client.close());

          final authCookie = await _signIn(client);
          final preCookie =
              (await client.get(
                '/auth/session',
                headers: {
                  HttpHeaders.cookieHeader: [_cookieHeader(authCookie)],
                },
              )).cookie('test_session') ??
              authCookie;

          final updateResponse = await client.postJson(
            '/update',
            <String, dynamic>{},
            headers: {
              HttpHeaders.cookieHeader: [_cookieHeader(preCookie)],
            },
          );
          updateResponse.assertStatus(HttpStatus.ok);

          final postCookie = updateResponse.cookie('test_session') ?? preCookie;
          final sessionResponse = await client.get(
            '/auth/session',
            headers: {
              HttpHeaders.cookieHeader: [_cookieHeader(postCookie)],
            },
          );
          sessionResponse.assertStatus(HttpStatus.ok);
          final body = _decodeJson(sessionResponse)!;
          expect(body['user']['name'], equals('SessionAuth Updated'));
          expect(body['user']['roles'], contains('admin'));
        },
      );

      test('jwt strategy: reissues JWT via SessionAuth facade', () async {
        final manager = _jwtManager();
        final engine = _authEngine(
          manager,
          configure: (engine) {
            engine.post('/update', (ctx) async {
              await SessionAuth.updateSession(
                ctx,
                AuthPrincipal(
                  id: 'user-1',
                  roles: const ['billing'],
                  attributes: const {
                    'email': 'user@example.com',
                    'name': 'JWT Updated',
                  },
                ),
              );
              return ctx.json({'ok': true});
            });
          },
        );

        await engine.initialize();
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(() async => await client.close());

        final authCookie = await _signIn(client);

        final updateResponse = await client.postJson(
          '/update',
          <String, dynamic>{},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(authCookie)],
          },
        );
        updateResponse.assertStatus(HttpStatus.ok);

        // Should have reissued the JWT cookie.
        final newJwt = updateResponse.cookie('routed_auth_token');
        expect(newJwt, isNotNull, reason: 'JWT cookie should be reissued');

        // Verify the new token resolves correctly.
        final cookies = <String>[_cookieHeader(authCookie)];
        final newSession = updateResponse.cookie('test_session');
        if (newSession != null) cookies.add(_cookieHeader(newSession));
        cookies.add(_cookieHeader(newJwt!));

        final sessionResponse = await client.get(
          '/auth/session',
          headers: {HttpHeaders.cookieHeader: cookies},
        );
        sessionResponse.assertStatus(HttpStatus.ok);
        final body = _decodeJson(sessionResponse)!;
        expect(body['user']['name'], equals('JWT Updated'));
        expect(body['user']['roles'], contains('billing'));
        expect(body['strategy'], equals('jwt'));
      });
    });

    group('without AuthManager (session-only fallback)', () {
      test(
        'falls back to SessionAuth.login when no updater is registered',
        () async {
          // Clear any updater wired by previous tests.
          SessionAuth.setSessionUpdater(null);

          final engine = _minimalSessionEngine(
            configure: (engine) {
              // Manually log in and then update — no AuthManager involved.
              engine.post('/login', (ctx) async {
                final principal = AuthPrincipal(
                  id: 'user-1',
                  roles: const ['member'],
                  attributes: const {'name': 'Original'},
                );
                await SessionAuth.login(ctx, principal);
                return ctx.json({'ok': true});
              });

              engine.post('/update', (ctx) async {
                final updated = AuthPrincipal(
                  id: 'user-1',
                  roles: const ['member', 'editor'],
                  attributes: const {'name': 'Fallback Updated'},
                );
                // No AuthManager in container — should fallback gracefully.
                await SessionAuth.updateSession(ctx, updated);
                return ctx.json({'ok': true});
              });

              engine.get('/me', (ctx) {
                final principal = SessionAuth.current(ctx);
                if (principal == null) {
                  return ctx.json(<String, dynamic>{
                    'error': 'not_authenticated',
                  }, statusCode: HttpStatus.unauthorized);
                }
                return ctx.json(principal.toJson());
              });
            },
          );

          await engine.initialize();
          final client = TestClient(RoutedRequestHandler(engine));
          addTearDown(() async => await client.close());

          // Login.
          final loginResponse = await client.postJson(
            '/login',
            <String, dynamic>{},
          );
          loginResponse.assertStatus(HttpStatus.ok);
          var cookie = loginResponse.cookie('test_session')!;

          // Verify initial state.
          final meBefore = await client.get(
            '/me',
            headers: {
              HttpHeaders.cookieHeader: [_cookieHeader(cookie)],
            },
          );
          meBefore.assertStatus(HttpStatus.ok);
          expect(
            _decodeJson(meBefore)!['attributes']['name'],
            equals('Original'),
          );
          cookie = meBefore.cookie('test_session') ?? cookie;

          // Update via SessionAuth.updateSession (fallback path).
          final updateResponse = await client.postJson(
            '/update',
            <String, dynamic>{},
            headers: {
              HttpHeaders.cookieHeader: [_cookieHeader(cookie)],
            },
          );
          updateResponse.assertStatus(HttpStatus.ok);
          cookie = updateResponse.cookie('test_session') ?? cookie;

          // Verify the session reflects the update.
          final meAfter = await client.get(
            '/me',
            headers: {
              HttpHeaders.cookieHeader: [_cookieHeader(cookie)],
            },
          );
          meAfter.assertStatus(HttpStatus.ok);
          final afterBody = _decodeJson(meAfter)!;
          expect(afterBody['attributes']['name'], equals('Fallback Updated'));
          expect(afterBody['roles'], contains('editor'));
        },
      );
    });
  });
}
