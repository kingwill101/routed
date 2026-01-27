/// Integration tests demonstrating practical auth flows for each authentication type.
///
/// These tests use the routed_testing package to make HTTP requests
/// against an auth-enabled Engine, testing the full request/response cycle.
import 'dart:convert';
import 'dart:io';

import 'package:routed/auth.dart';
import 'package:routed/routed.dart';
import 'package:routed/session.dart';
import 'package:routed/src/sessions/middleware.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'package:test/test.dart';

// ============================================================================
// TEST UTILITIES
// ============================================================================

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

/// Creates an engine with session + auth support.
Engine _authEngine(AuthManager manager, {SessionConfig? sessionConfig}) {
  sessionConfig ??= _sessionConfig();
  final engine = Engine(
    config: EngineConfig(
      security: const EngineSecurityFeatures(csrfProtection: false),
    ),
    providers: Engine.defaultProviders,
    options: [withSessionConfig(sessionConfig)],
  );
  engine.addGlobalMiddleware(
    sessionMiddleware(
      store: sessionConfig.store,
      name: sessionConfig.cookieName,
    ),
  );
  engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());
  AuthRoutes(manager).register(engine.defaultRouter);
  return engine;
}

String _cookieHeader(Cookie cookie) => '${cookie.name}=${cookie.value}';

void main() {
  group('Auth Flow Integration Tests', () {
    // ========================================================================
    // 1. CREDENTIALS AUTHENTICATION
    // ========================================================================
    group('1. Credentials Authentication', () {
      // Simulated user database
      final users = <String, Map<String, dynamic>>{
        'alice': {
          'id': 'user-alice',
          'email': 'alice@example.com',
          'password': 'secret123',
          'name': 'Alice Smith',
        },
      };

      late AuthManager manager;
      late Engine engine;

      setUp(() async {
        manager = AuthManager(
          AuthOptions(
            providers: [
              CredentialsProvider(
                authorize: (ctx, provider, credentials) async {
                  final username = credentials.username ?? credentials.email;
                  final userData = users[username];
                  if (userData == null) return null;
                  if (userData['password'] != credentials.password) {
                    return null;
                  }
                  return AuthUser(
                    id: userData['id'] as String,
                    email: userData['email'] as String,
                    name: userData['name'] as String,
                  );
                },
                register: (ctx, provider, credentials) async {
                  final username = credentials.username ?? credentials.email;
                  if (users.containsKey(username)) return null;
                  final id = 'user-${users.length + 1}';
                  users[username!] = {
                    'id': id,
                    'email': credentials.email,
                    'password': credentials.password,
                    'name': username,
                  };
                  return AuthUser(
                    id: id,
                    email: credentials.email,
                    name: username,
                  );
                },
              ),
            ],
            sessionStrategy: AuthSessionStrategy.session,
            enforceCsrf: false,
          ),
        );
        engine = _authEngine(manager);
        await engine.initialize();
      });

      test('successful login with valid credentials', () async {
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);

        // Get session cookie first
        final csrfResponse = await client.get('/auth/csrf');
        final sessionCookie = csrfResponse.cookie('test_session');

        final response = await client.postJson(
          '/auth/signin/credentials',
          {'username': 'alice', 'password': 'secret123'},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
          },
        );

        response.assertStatus(200);
        response.assertJson((json) {
          json.has('user').scope('user', (user) {
            user
              ..where('id', 'user-alice')
              ..where('email', 'alice@example.com')
              ..where('name', 'Alice Smith')
              ..etc();
          }).etc();
        });
      });

      test('failed login with wrong password', () async {
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);

        final csrfResponse = await client.get('/auth/csrf');
        final sessionCookie = csrfResponse.cookie('test_session');

        final response = await client.postJson(
          '/auth/signin/credentials',
          {'username': 'alice', 'password': 'wrongpassword'},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
          },
        );

        response.assertStatus(401);
        response.assertJson((json) {
          json.where('error', 'invalid_credentials').etc();
        });
      });

      test('failed login with non-existent user', () async {
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);

        final csrfResponse = await client.get('/auth/csrf');
        final sessionCookie = csrfResponse.cookie('test_session');

        final response = await client.postJson(
          '/auth/signin/credentials',
          {'username': 'nobody', 'password': 'password'},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
          },
        );

        response.assertStatus(401);
        response.assertJson((json) {
          json.where('error', 'invalid_credentials').etc();
        });
      });

      test('register new user and then login', () async {
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);

        final csrfResponse = await client.get('/auth/csrf');
        final sessionCookie = csrfResponse.cookie('test_session');
        final headers = {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
        };

        // First register
        final registerResponse = await client.postJson(
          '/auth/register/credentials',
          {
            'username': 'bob',
            'email': 'bob@example.com',
            'password': 'newpassword',
          },
          headers: headers,
        );

        registerResponse.assertStatus(200);
        registerResponse.assertJson((json) {
          json.has('user').scope('user', (user) {
            user
              ..where('email', 'bob@example.com')
              ..where('name', 'bob')
              ..etc();
          }).etc();
        });

        // Then login with same credentials
        final loginResponse = await client.postJson(
          '/auth/signin/credentials',
          {'username': 'bob', 'password': 'newpassword'},
          headers: headers,
        );

        loginResponse.assertStatus(200);
      });

      test('session persists after login', () async {
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);

        final csrfResponse = await client.get('/auth/csrf');
        var sessionCookie = csrfResponse.cookie('test_session')!;

        // Login
        final loginResponse = await client.postJson(
          '/auth/signin/credentials',
          {'username': 'alice', 'password': 'secret123'},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
          },
        );
        loginResponse.assertStatus(200);

        // Update session cookie if a new one was returned
        sessionCookie = loginResponse.cookie('test_session') ?? sessionCookie;

        // Check session
        final sessionResponse = await client.get(
          '/auth/session',
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
          },
        );
        sessionResponse.assertStatus(200);
        sessionResponse.assertJson((json) {
          json.has('user').scope('user', (user) {
            user.where('id', 'user-alice').etc();
          }).etc();
        });
      });
    });

    // ========================================================================
    // 2. EMAIL (MAGIC LINK) AUTHENTICATION
    // ========================================================================
    group('2. Email (Magic Link) Authentication', () {
      String? capturedToken;
      String? capturedEmail;

      late AuthManager manager;
      late Engine engine;

      setUp(() async {
        capturedToken = null;
        capturedEmail = null;

        manager = AuthManager(
          AuthOptions(
            providers: [
              EmailProvider(
                sendVerificationRequest: (ctx, provider, request) async {
                  capturedToken = request.token;
                  capturedEmail = request.email;
                },
                tokenExpiry: const Duration(minutes: 10),
              ),
            ],
            sessionStrategy: AuthSessionStrategy.session,
            enforceCsrf: false,
          ),
        );
        engine = _authEngine(manager);
        await engine.initialize();
      });

      test('request magic link sends verification', () async {
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);

        final csrfResponse = await client.get('/auth/csrf');
        final sessionCookie = csrfResponse.cookie('test_session');

        final response = await client.postJson(
          '/auth/signin/email',
          {'email': 'user@example.com'},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
          },
        );

        response.assertStatus(200);
        response.assertJson((json) {
          json
            ..where('status', 'verification_sent')
            ..where('email', 'user@example.com')
            ..etc();
        });

        // Verify token was captured
        expect(capturedToken, isNotNull);
        expect(capturedEmail, equals('user@example.com'));
      });

      test('complete magic link verification creates session', () async {
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);

        final csrfResponse = await client.get('/auth/csrf');
        var sessionCookie = csrfResponse.cookie('test_session')!;

        // Step 1: Request magic link
        await client.postJson(
          '/auth/signin/email',
          {'email': 'magicuser@example.com'},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
          },
        );

        // Step 2: Use the captured token to verify
        final callbackResponse = await client.get(
          '/auth/callback/email?token=$capturedToken&email=$capturedEmail',
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
          },
        );

        callbackResponse.assertStatus(200);
        callbackResponse.assertJson((json) {
          json.has('user').scope('user', (user) {
            user.where('email', capturedEmail).etc();
          }).etc();
        });
      });

      test('invalid token returns error', () async {
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);

        final response = await client.get(
          '/auth/callback/email?token=invalid-token&email=test@example.com',
        );

        response.assertStatus(401);
        response.assertJson((json) {
          json.where('error', 'invalid_token').etc();
        });
      });

      test('missing token parameter returns error', () async {
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);

        final response = await client.get(
          '/auth/callback/email?email=test@example.com',
        );

        response.assertStatus(400);
        response.assertJson((json) {
          json.where('error', 'missing_token').etc();
        });
      });
    });

    // ========================================================================
    // 3. JWT SESSION STRATEGY
    // ========================================================================
    group('3. JWT Session Strategy', () {
      late AuthManager manager;
      late Engine engine;

      setUp(() async {
        manager = AuthManager(
          AuthOptions(
            providers: [
              CredentialsProvider(
                authorize: (ctx, provider, credentials) async {
                  if (credentials.username == 'jwt-user' &&
                      credentials.password == 'jwt-pass') {
                    return AuthUser(
                      id: 'jwt-user-1',
                      email: 'jwt@example.com',
                      name: 'JWT User',
                      roles: ['admin', 'user'],
                    );
                  }
                  return null;
                },
              ),
            ],
            sessionStrategy: AuthSessionStrategy.jwt,
            jwtOptions: const JwtSessionOptions(
              secret: 'test-secret-key-for-jwt-signing-32chars',
              maxAge: Duration(hours: 1),
              cookieName: 'auth.jwt',
            ),
            enforceCsrf: false,
          ),
        );
        engine = _authEngine(manager);
        await engine.initialize();
      });

      test('successful login returns JWT token in response', () async {
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);

        final csrfResponse = await client.get('/auth/csrf');
        final sessionCookie = csrfResponse.cookie('test_session');

        final response = await client.postJson(
          '/auth/signin/credentials',
          {'username': 'jwt-user', 'password': 'jwt-pass'},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
          },
        );

        response.assertStatus(200);
        response.assertJson((json) {
          json
            ..has('user')
            ..has('token')
            ..where('strategy', 'jwt')
            ..scope('user', (user) {
              user
                ..where('id', 'jwt-user-1')
                ..where('email', 'jwt@example.com')
                ..has('roles')
                ..etc();
            })
            ..etc();
        });
      });

      test('session endpoint returns user from JWT cookie', () async {
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);

        final csrfResponse = await client.get('/auth/csrf');
        var sessionCookie = csrfResponse.cookie('test_session')!;

        // First login
        final loginResponse = await client.postJson(
          '/auth/signin/credentials',
          {'username': 'jwt-user', 'password': 'jwt-pass'},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
          },
        );
        loginResponse.assertStatus(200);

        // Get JWT cookie
        final jwtCookie = loginResponse.cookie('auth.jwt');
        expect(jwtCookie, isNotNull);

        // Then check session - use JWT cookie
        final sessionResponse = await client.get(
          '/auth/session',
          headers: {
            HttpHeaders.cookieHeader: [
              _cookieHeader(sessionCookie),
              _cookieHeader(jwtCookie!),
            ],
          },
        );
        sessionResponse.assertStatus(200);
        sessionResponse.assertJson((json) {
          json.has('user').scope('user', (user) {
            user.where('id', 'jwt-user-1').etc();
          }).etc();
        });
      });

      test('JWT includes roles', () async {
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);

        final csrfResponse = await client.get('/auth/csrf');
        final sessionCookie = csrfResponse.cookie('test_session');

        final response = await client.postJson(
          '/auth/signin/credentials',
          {'username': 'jwt-user', 'password': 'jwt-pass'},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
          },
        );

        response.assertStatus(200);
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        expect(body['user']['roles'], containsAll(['admin', 'user']));
      });
    });

    // ========================================================================
    // 4. OAUTH FLOW (REDIRECT TESTING)
    // ========================================================================
    group('4. OAuth Flow', () {
      late AuthManager manager;
      late Engine engine;

      setUp(() async {
        manager = AuthManager(
          AuthOptions(
            providers: [
              OAuthProvider<Map<String, dynamic>>(
                id: 'test-oauth',
                name: 'Test OAuth',
                clientId: 'test-client-id',
                clientSecret: 'test-client-secret',
                redirectUri: 'http://localhost:8080/auth/callback/test-oauth',
                authorizationEndpoint: Uri.parse(
                  'https://oauth.example.com/authorize',
                ),
                tokenEndpoint: Uri.parse('https://oauth.example.com/token'),
                scopes: ['openid', 'profile', 'email'],
                profile: (data) => AuthUser(
                  id: data['sub']?.toString() ?? '',
                  email: data['email']?.toString(),
                  name: data['name']?.toString(),
                ),
              ),
            ],
            sessionStrategy: AuthSessionStrategy.session,
            enforceCsrf: false,
          ),
        );
        engine = _authEngine(manager);
        await engine.initialize();
      });

      test('GET signin returns redirect to OAuth provider', () async {
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);

        final csrfResponse = await client.get('/auth/csrf');
        final sessionCookie = csrfResponse.cookie('test_session');

        final response = await client.get(
          '/auth/signin/test-oauth',
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
          },
        );

        // The response will be a redirect
        response.assertStatus(302);

        final location = response.headers['location']?.first;
        expect(location, isNotNull);

        final redirectUri = Uri.parse(location!);
        expect(redirectUri.host, equals('oauth.example.com'));
        expect(redirectUri.path, equals('/authorize'));
        expect(
          redirectUri.queryParameters['client_id'],
          equals('test-client-id'),
        );
        expect(redirectUri.queryParameters['response_type'], equals('code'));
        expect(redirectUri.queryParameters['scope'], contains('openid'));
        expect(redirectUri.queryParameters['state'], isNotEmpty);
      });

      test('callback without code returns error', () async {
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);

        final response = await client.get(
          '/auth/callback/test-oauth?state=test-state',
        );

        response.assertStatus(400);
        response.assertJson((json) {
          json.where('error', 'missing_code').etc();
        });
      });

      test('callback with invalid state returns error', () async {
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);

        final csrfResponse = await client.get('/auth/csrf');
        final sessionCookie = csrfResponse.cookie('test_session');

        final response = await client.get(
          '/auth/callback/test-oauth?code=test-code&state=invalid-state',
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
          },
        );

        response.assertStatus(401);
        response.assertJson((json) {
          json.where('error', 'invalid_state').etc();
        });
      });
    });

    // ========================================================================
    // 5. AUTH PROVIDERS ENDPOINT
    // ========================================================================
    group('5. Auth Providers Endpoint', () {
      late AuthManager manager;
      late Engine engine;

      setUp(() async {
        manager = AuthManager(
          AuthOptions(
            providers: [
              CredentialsProvider(),
              EmailProvider(
                sendVerificationRequest: (ctx, provider, request) async {},
              ),
              OAuthProvider<Map<String, dynamic>>(
                id: 'github',
                name: 'GitHub',
                clientId: 'client-id',
                clientSecret: 'secret',
                redirectUri: 'http://localhost/callback',
                authorizationEndpoint: Uri.parse('https://github.com/auth'),
                tokenEndpoint: Uri.parse('https://github.com/token'),
                profile: (p) => AuthUser(id: p['id']?.toString() ?? ''),
              ),
            ],
            enforceCsrf: false,
          ),
        );
        engine = _authEngine(manager);
        await engine.initialize();
      });

      test('lists all configured providers', () async {
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);

        final response = await client.get('/auth/providers');

        response.assertStatus(200);
        response.assertJson((json) {
          json.has('providers').etc();
        });

        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final providers = body['providers'] as List;
        expect(providers.length, equals(3));

        final types = providers.map((p) => p['type']).toList();
        expect(types, contains('credentials'));
        expect(types, contains('email'));
        expect(types, contains('oauth'));
      });

      test('provider list includes id and name', () async {
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);

        final response = await client.get('/auth/providers');
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final providers = body['providers'] as List;

        for (final provider in providers) {
          expect(provider['id'], isNotNull);
          expect(provider['name'], isNotNull);
          expect(provider['type'], isNotNull);
        }
      });
    });

    // ========================================================================
    // 6. CSRF PROTECTION
    // ========================================================================
    group('6. CSRF Protection', () {
      late AuthManager manager;
      late Engine engine;

      setUp(() async {
        manager = AuthManager(
          AuthOptions(
            enforceCsrf: true, // Enable CSRF
            providers: [
              CredentialsProvider(
                authorize: (ctx, provider, credentials) async {
                  return AuthUser(id: 'csrf-user');
                },
              ),
            ],
          ),
        );
        engine = _authEngine(manager);
        await engine.initialize();
      });

      test('POST without CSRF token fails', () async {
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);

        final csrfResponse = await client.get('/auth/csrf');
        final sessionCookie = csrfResponse.cookie('test_session');

        final response = await client.postJson(
          '/auth/signin/credentials',
          {'username': 'test', 'password': 'test'},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
          },
        );

        response.assertStatus(403);
        response.assertJson((json) {
          json.where('error', 'invalid_csrf').etc();
        });
      });

      test('POST with valid CSRF token in body succeeds', () async {
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);

        // First get CSRF token
        final csrfResponse = await client.get('/auth/csrf');
        csrfResponse.assertStatus(200);
        final csrfBody = jsonDecode(csrfResponse.body) as Map<String, dynamic>;
        final csrfToken = csrfBody['csrfToken'] as String;
        final sessionCookie = csrfResponse.cookie('test_session');

        // Then use it in signin request
        final response = await client.postJson(
          '/auth/signin/credentials',
          {'username': 'test', 'password': 'test', '_csrf': csrfToken},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
          },
        );

        response.assertStatus(200);
      });

      test('X-CSRF-Token header also works', () async {
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);

        // First get CSRF token
        final csrfResponse = await client.get('/auth/csrf');
        final csrfBody = jsonDecode(csrfResponse.body) as Map<String, dynamic>;
        final csrfToken = csrfBody['csrfToken'] as String;
        final sessionCookie = csrfResponse.cookie('test_session');

        // Use header instead of body
        final response = await client.post(
          '/auth/signin/credentials',
          jsonEncode({'username': 'test', 'password': 'test'}),
          headers: {
            'Content-Type': ['application/json'],
            'X-CSRF-Token': [csrfToken],
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
          },
        );

        response.assertStatus(200);
      });
    });

    // ========================================================================
    // 7. SESSION MANAGEMENT
    // ========================================================================
    group('7. Session Management', () {
      late AuthManager manager;
      late Engine engine;

      setUp(() async {
        manager = AuthManager(
          AuthOptions(
            enforceCsrf: false,
            providers: [
              CredentialsProvider(
                authorize: (ctx, provider, credentials) async {
                  return AuthUser(
                    id: 'session-user',
                    email: 'session@example.com',
                  );
                },
              ),
            ],
            sessionStrategy: AuthSessionStrategy.session,
          ),
        );
        engine = _authEngine(manager);
        await engine.initialize();
      });

      test('session endpoint returns null when not authenticated', () async {
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);

        final response = await client.get('/auth/session');
        response.assertStatus(200);
        // Response body should be null
        expect(response.body, equals('null'));
      });

      test('sign out clears session', () async {
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);

        final csrfResponse = await client.get('/auth/csrf');
        var sessionCookie = csrfResponse.cookie('test_session')!;

        // Login first
        final loginResponse = await client.postJson(
          '/auth/signin/credentials',
          {'username': 'test', 'password': 'test'},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
          },
        );
        sessionCookie = loginResponse.cookie('test_session') ?? sessionCookie;

        // Verify session exists
        final sessionBefore = await client.get(
          '/auth/session',
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
          },
        );
        sessionBefore.assertStatus(200);
        expect(sessionBefore.body, isNot(equals('null')));

        // Sign out
        final signOutResponse = await client.post(
          '/auth/signout',
          '',
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
          },
        );
        signOutResponse.assertStatus(200);
        signOutResponse.assertJson((json) {
          json.where('ok', true).etc();
        });

        // Verify session is cleared
        final sessionAfter = await client.get(
          '/auth/session',
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
          },
        );
        sessionAfter.assertStatus(200);
        expect(sessionAfter.body, equals('null'));
      });
    });

    // ========================================================================
    // 8. AUTH CALLBACKS
    // ========================================================================
    group('8. Auth Callbacks', () {
      var signInCallbackCalled = false;
      var sessionCallbackCalled = false;

      late AuthManager manager;
      late Engine engine;

      setUp(() async {
        signInCallbackCalled = false;
        sessionCallbackCalled = false;

        manager = AuthManager(
          AuthOptions(
            enforceCsrf: false,
            providers: [
              CredentialsProvider(
                authorize: (ctx, provider, credentials) async {
                  return AuthUser(
                    id: 'callback-user',
                    email: credentials.email ?? 'test@example.com',
                  );
                },
              ),
            ],
            callbacks: AuthCallbacks(
              signIn: (context) async {
                signInCallbackCalled = true;
                // Block users with certain email domain
                if (context.user.email?.endsWith('@blocked.com') == true) {
                  return const AuthSignInResult.deny();
                }
                return const AuthSignInResult.allow();
              },
              session: (context) async {
                sessionCallbackCalled = true;
                // Add custom data to session payload
                return {...context.payload, 'customField': 'customValue'};
              },
            ),
          ),
        );
        engine = _authEngine(manager);
        await engine.initialize();
      });

      test('signIn callback is invoked', () async {
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);

        final csrfResponse = await client.get('/auth/csrf');
        final sessionCookie = csrfResponse.cookie('test_session');

        await client.postJson(
          '/auth/signin/credentials',
          {'email': 'user@allowed.com', 'password': 'test'},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
          },
        );

        expect(signInCallbackCalled, isTrue);
      });

      test('signIn callback can block login', () async {
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);

        final csrfResponse = await client.get('/auth/csrf');
        final sessionCookie = csrfResponse.cookie('test_session');

        final response = await client.postJson(
          '/auth/signin/credentials',
          {'email': 'user@blocked.com', 'password': 'test'},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
          },
        );

        response.assertStatus(401);
        expect(signInCallbackCalled, isTrue);
      });

      test('session callback adds custom data', () async {
        final client = TestClient(RoutedRequestHandler(engine));
        addTearDown(client.close);

        final csrfResponse = await client.get('/auth/csrf');
        var sessionCookie = csrfResponse.cookie('test_session')!;

        final loginResponse = await client.postJson(
          '/auth/signin/credentials',
          {'email': 'user@allowed.com', 'password': 'test'},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
          },
        );
        sessionCookie = loginResponse.cookie('test_session') ?? sessionCookie;

        final sessionResponse = await client.get(
          '/auth/session',
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
          },
        );
        sessionResponse.assertStatus(200);
        sessionResponse.assertJson((json) {
          json.where('customField', 'customValue').etc();
        });

        expect(sessionCallbackCalled, isTrue);
      });
    });
  });
}
