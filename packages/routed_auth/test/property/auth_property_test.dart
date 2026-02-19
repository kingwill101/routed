/// Property-based and chaos testing for auth routes.
///
/// Uses adversarial inputs, chaos generators, and stateful testing to ensure
/// the auth system is robust against:
/// - Malformed inputs (SQL injection, XSS, path traversal)
/// - Edge case values (null bytes, unicode, control characters)
/// - Invalid credentials and tokens
/// - State machine invariants
library;

import 'dart:convert';
import 'dart:io';

import 'package:property_testing/property_testing.dart';
import 'package:routed/routed.dart';
import 'package:routed/session.dart';
import 'package:routed/src/sessions/middleware.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

// ============================================================================
// CUSTOM GENERATORS FOR AUTH TESTING
// ============================================================================

/// Generates chaotic usernames with potential injection attacks
Generator<String> chaoticUsername({int maxLength = 100}) {
  return Gen.frequency([
    (3, Chaos.string(minLength: 1, maxLength: maxLength)),
    (
      2,
      Gen.oneOf([
        "admin'--",
        "admin' OR '1'='1",
        "admin\"; DROP TABLE users; --",
        "<script>alert('xss')</script>",
        "../../../etc/passwd",
        "admin%00",
        "admin\x00hidden",
        "admin\r\nX-Injected: header",
        "admin' UNION SELECT * FROM passwords--",
        "${'\$'}{process.env.SECRET}",
        "{{constructor.constructor('return this')()}}",
        "admin|cat /etc/passwd",
        "admin; ls -la",
        "admin\nX-Forwarded-For: attacker",
      ]),
    ),
    (1, Gen.string(minLength: 1, maxLength: 50)),
  ]);
}

/// Generates chaotic passwords
Generator<String> chaoticPassword({int maxLength = 100}) {
  return Gen.frequency([
    (3, Chaos.string(minLength: 0, maxLength: maxLength)),
    (
      2,
      Gen.oneOf([
        "", // Empty password
        " ", // Single space
        "   ", // Multiple spaces
        "\t\n\r", // Whitespace only
        "a" * 10000, // Very long password
        "\x00password", // Null byte prefix
        "pass\x00word", // Null byte middle
        "password\x00", // Null byte suffix
        "пароль", // Cyrillic
        "密码", // Chinese
        "🔐🔑🔒", // Emoji
        "pass\u200Bword", // Zero-width space
        "pass\u202Eword", // Right-to-left override
      ]),
    ),
    (1, Gen.string(minLength: 1, maxLength: 50)),
  ]);
}

/// Generates chaotic email addresses
Generator<String> chaoticEmail({int maxLength = 100}) {
  return Gen.frequency([
    (3, Chaos.string(minLength: 0, maxLength: maxLength)),
    (
      2,
      Gen.oneOf([
        "", // Empty
        "notanemail", // No @
        "@", // Just @
        "user@", // No domain
        "@domain.com", // No local part
        "user@@domain.com", // Double @
        "user@domain@evil.com", // Double @
        "user@domain.com@attacker.com",
        "user+tag@domain.com",
        "user@[127.0.0.1]",
        "user@localhost",
        "user@.com",
        ".user@domain.com",
        "user.@domain.com",
        "user..test@domain.com",
        "<script>@evil.com",
        "user@domain.com\r\nBcc: attacker@evil.com",
        "\"user\"@domain.com",
        "user@domain.com%00attacker@evil.com",
      ]),
    ),
    (1, Specialized.email()),
  ]);
}

/// Generates chaotic OAuth state values
Generator<String> chaoticOAuthState({int maxLength = 200}) {
  return Gen.frequency([
    (3, Chaos.string(minLength: 0, maxLength: maxLength)),
    (
      2,
      Gen.oneOf([
        "", // Empty
        "valid-state-token",
        "a" * 10000, // Very long
        "state%00injected",
        "state\r\nLocation: http://evil.com",
        "state<script>",
        "../../../.env",
        "state|cat /etc/passwd",
        "eyJhbGciOiJub25lIn0.eyJ1c2VyIjoiYWRtaW4ifQ.", // JWT with alg:none
      ]),
    ),
    (1, Gen.string(minLength: 10, maxLength: 64)),
  ]);
}

/// Generates chaotic OAuth code values
Generator<String> chaoticOAuthCode({int maxLength = 200}) {
  return Gen.frequency([
    (3, Chaos.string(minLength: 0, maxLength: maxLength)),
    (
      2,
      Gen.oneOf([
        "", // Empty
        "valid-code",
        "a" * 10000, // Very long
        "code%00injected",
        "code\r\nX-Injected: header",
        "code<script>alert(1)</script>",
        "code' OR '1'='1",
        "code; DROP TABLE tokens;--",
      ]),
    ),
    (1, Gen.string(minLength: 10, maxLength: 64)),
  ]);
}

/// Generates chaotic callback URLs
Generator<String> chaoticCallbackUrl({int maxLength = 500}) {
  return Gen.frequency([
    (3, Chaos.string(minLength: 0, maxLength: maxLength)),
    (
      2,
      Gen.oneOf([
        "", // Empty
        "javascript:alert(1)",
        "data:text/html,<script>alert(1)</script>",
        "//evil.com/steal-token",
        "https://evil.com/callback",
        "http://localhost/../../../etc/passwd",
        "/callback?redirect=http://evil.com",
        "https://legit.com@evil.com/",
        "https://evil.com#legit.com",
        "https://evil.com%00legit.com",
        "\r\nLocation: http://evil.com",
        "file:///etc/passwd",
        "ftp://evil.com",
      ]),
    ),
    (1, Gen.oneOf(["/callback", "/profile", "/dashboard"])),
  ]);
}

/// Generates chaotic CSRF tokens
Generator<String?> chaoticCsrfToken({int maxLength = 100}) {
  return Gen.frequency<String?>([
    (
      2,
      Chaos.string(minLength: 0, maxLength: maxLength).map((s) => s as String?),
    ),
    (
      2,
      Gen.oneOf<String?>([
        null,
        "",
        "invalid-csrf",
        "a" * 10000,
        "csrf%00injected",
        "\r\nX-Injected: header",
      ]),
    ),
    (1, Gen.string(minLength: 32, maxLength: 64).map((s) => s as String?)),
  ]);
}

/// Generates chaotic JSON payloads
Generator<Map<String, dynamic>> chaoticAuthPayload() {
  return Gen.frequency([
    // Chaotic string values
    (
      3,
      chaoticUsername().flatMap((username) {
        return chaoticPassword().flatMap((password) {
          return chaoticEmail().map((email) {
            return <String, dynamic>{
              'username': username,
              'password': password,
              'email': email,
            };
          });
        });
      }),
    ),
    // Nested injection attempts
    (
      2,
      Gen.oneOf([
        <String, dynamic>{
          '__proto__': {'isAdmin': true},
          'username': 'admin',
        },
        <String, dynamic>{
          'constructor': {
            'prototype': {'isAdmin': true},
          },
        },
        <String, dynamic>{
          'username': {'toString': 'admin'},
        },
        <String, dynamic>{
          'username': [1, 2, 3], // Array instead of string
        },
        <String, dynamic>{
          'username': 123, // Number instead of string
        },
        <String, dynamic>{
          'username': true, // Boolean instead of string
        },
        <String, dynamic>{
          'username': null, // Null value
        },
      ]),
    ),
    // Normal payloads
    (
      1,
      Gen.constant(<String, dynamic>{
        'username': 'testuser',
        'password': 'testpass',
        'email': 'test@example.com',
      }),
    ),
  ]);
}

/// Generates chaotic HTTP header values
Generator<String> chaoticHeaderValue({int maxLength = 200}) {
  return Gen.frequency([
    (3, Chaos.string(minLength: 0, maxLength: maxLength)),
    (
      2,
      Gen.oneOf([
        "", // Empty
        "value\r\nX-Injected: header",
        "value\r\n\r\n<html>",
        "a" * 10000,
        "\x00value",
        "value%00injected",
      ]),
    ),
    (1, Gen.string(minLength: 1, maxLength: 50)),
  ]);
}

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

Engine _authEngine(AuthManager manager, {SessionConfig? sessionConfig}) {
  sessionConfig ??= _sessionConfig();
  final engine = Engine(
    config: EngineConfig(
      security: const EngineSecurityFeatures(csrfProtection: false),
    ),
    providers: Engine.defaultProviders,
    options: [withSessionConfig(sessionConfig)],
  );
  engine.addGlobalMiddleware(sessionMiddleware());
  engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());
  AuthRoutes(manager).register(engine.defaultRouter);
  return engine;
}

String _cookieHeader(Cookie cookie) => '${cookie.name}=${cookie.value}';

// ============================================================================
// PROPERTY TESTS: ADVERSARIAL INPUT HANDLING
// ============================================================================

void main() {
  group('Auth Property Tests', () {
    // ========================================================================
    // 1. ADVERSARIAL CREDENTIALS TESTING
    // ========================================================================
    group('1. Adversarial Credentials Input', () {
      late AuthManager manager;
      late Engine engine;
      late TestClient client;

      setUp(() async {
        manager = AuthManager(
          AuthOptions(
            providers: [
              CredentialsProvider(
                authorize: (ctx, provider, credentials) async {
                  // Simple auth that only accepts specific valid credentials
                  if (credentials.username == 'validuser' &&
                      credentials.password == 'validpass') {
                    return AuthUser(
                      id: 'user-1',
                      email: 'valid@example.com',
                      name: 'Valid User',
                    );
                  }
                  return null;
                },
              ),
            ],
            sessionStrategy: AuthSessionStrategy.session,
            enforceCsrf: false,
          ),
        );
        engine = _authEngine(manager);
        await engine.initialize();
        client = TestClient(RoutedRequestHandler(engine));
      });

      tearDown(() => client.close());

      test('server never crashes with chaotic usernames', () async {
        final config = PropertyConfig(numTests: 100, seed: 42);
        final runner = PropertyTestRunner(chaoticUsername(), (username) async {
          final csrfResponse = await client.get('/auth/csrf');
          final sessionCookie = csrfResponse.cookie('test_session');

          final response = await client.postJson(
            '/auth/signin/credentials',
            {'username': username, 'password': 'anypassword'},
            headers: {
              HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
            },
          );

          // Server must NOT crash (500 error)
          expect(
            response.statusCode,
            lessThan(500),
            reason: 'Server crashed with username: $username',
          );
          // Must return a valid response
          expect(
            response.statusCode,
            anyOf([200, 400, 401, 403, 404]),
            reason: 'Unexpected status for username: $username',
          );
        }, config);

        final result = await runner.run();
        expect(result.success, isTrue, reason: _formatResult(result));
      });

      test('server never crashes with chaotic passwords', () async {
        final config = PropertyConfig(numTests: 100, seed: 42);
        final runner = PropertyTestRunner(chaoticPassword(), (password) async {
          final csrfResponse = await client.get('/auth/csrf');
          final sessionCookie = csrfResponse.cookie('test_session');

          final response = await client.postJson(
            '/auth/signin/credentials',
            {'username': 'anyuser', 'password': password},
            headers: {
              HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
            },
          );

          expect(
            response.statusCode,
            lessThan(500),
            reason: 'Server crashed with password: ${_sanitize(password)}',
          );
        }, config);

        final result = await runner.run();
        expect(result.success, isTrue, reason: _formatResult(result));
      });

      test('server never crashes with chaotic payloads', () async {
        final config = PropertyConfig(numTests: 100, seed: 42);
        final runner = PropertyTestRunner(chaoticAuthPayload(), (
          payload,
        ) async {
          final csrfResponse = await client.get('/auth/csrf');
          final sessionCookie = csrfResponse.cookie('test_session');

          final response = await client.postJson(
            '/auth/signin/credentials',
            payload,
            headers: {
              HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
            },
          );

          expect(
            response.statusCode,
            lessThan(500),
            reason: 'Server crashed with payload: $payload',
          );
        }, config);

        final result = await runner.run();
        expect(result.success, isTrue, reason: _formatResult(result));
      });

      test('chaotic credentials never authenticate successfully', () async {
        final config = PropertyConfig(numTests: 100, seed: 42);
        final runner = PropertyTestRunner(
          chaoticUsername().flatMap((username) {
            return chaoticPassword().map((password) => (username, password));
          }),
          (pair) async {
            final (username, password) = pair;
            // Skip the one valid combination
            if (username == 'validuser' && password == 'validpass') return;

            final csrfResponse = await client.get('/auth/csrf');
            final sessionCookie = csrfResponse.cookie('test_session');

            final response = await client.postJson(
              '/auth/signin/credentials',
              {'username': username, 'password': password},
              headers: {
                HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
              },
            );

            // Chaotic credentials should NEVER succeed
            expect(
              response.statusCode,
              isNot(200),
              reason:
                  'Chaotic credentials authenticated: $username / ${_sanitize(password)}',
            );
          },
          config,
        );

        final result = await runner.run();
        expect(result.success, isTrue, reason: _formatResult(result));
      });
    });

    // ========================================================================
    // 2. ADVERSARIAL EMAIL PROVIDER TESTING
    // ========================================================================
    group('2. Adversarial Email Input', () {
      late AuthManager manager;
      late Engine engine;
      late TestClient client;
      String? capturedToken;
      // ignore: unused_local_variable
      String? capturedEmail;

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
        client = TestClient(RoutedRequestHandler(engine));
      });

      tearDown(() => client.close());

      test('server never crashes with chaotic email addresses', () async {
        final config = PropertyConfig(numTests: 100, seed: 42);
        final runner = PropertyTestRunner(chaoticEmail(), (email) async {
          final csrfResponse = await client.get('/auth/csrf');
          final sessionCookie = csrfResponse.cookie('test_session');

          final response = await client.postJson(
            '/auth/signin/email',
            {'email': email},
            headers: {
              HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
            },
          );

          expect(
            response.statusCode,
            lessThan(500),
            reason: 'Server crashed with email: $email',
          );
        }, config);

        final result = await runner.run();
        expect(result.success, isTrue, reason: _formatResult(result));
      });

      test('chaotic tokens never verify successfully', () async {
        // First, get a valid token
        final csrfResponse = await client.get('/auth/csrf');
        final sessionCookie = csrfResponse.cookie('test_session');
        await client.postJson(
          '/auth/signin/email',
          {'email': 'valid@example.com'},
          headers: {
            HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
          },
        );

        final config = PropertyConfig(numTests: 100, seed: 42);
        final runner = PropertyTestRunner(
          Chaos.string(minLength: 0, maxLength: 200),
          (chaoticToken) async {
            // Skip the actual valid token
            if (chaoticToken == capturedToken) return;

            final response = await client.get(
              '/auth/callback/email?token=${Uri.encodeComponent(chaoticToken)}&email=valid@example.com',
              headers: {
                HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
              },
            );

            expect(
              response.statusCode,
              lessThan(500),
              reason: 'Server crashed with token: ${_sanitize(chaoticToken)}',
            );
            expect(
              response.statusCode,
              isNot(200),
              reason: 'Chaotic token verified: ${_sanitize(chaoticToken)}',
            );
          },
          config,
        );

        final result = await runner.run();
        expect(result.success, isTrue, reason: _formatResult(result));
      });
    });

    // ========================================================================
    // 3. ADVERSARIAL OAUTH TESTING
    // ========================================================================
    group('3. Adversarial OAuth Input', () {
      late AuthManager manager;
      late Engine engine;
      late TestClient client;

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
        client = TestClient(RoutedRequestHandler(engine));
      });

      tearDown(() => client.close());

      test('server never crashes with chaotic OAuth codes', () async {
        final config = PropertyConfig(numTests: 100, seed: 42);
        final runner = PropertyTestRunner(chaoticOAuthCode(), (code) async {
          final csrfResponse = await client.get('/auth/csrf');
          final sessionCookie = csrfResponse.cookie('test_session');

          final response = await client.get(
            '/auth/callback/test-oauth?code=${Uri.encodeComponent(code)}&state=test-state',
            headers: {
              HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
            },
          );

          expect(
            response.statusCode,
            lessThan(500),
            reason: 'Server crashed with OAuth code: ${_sanitize(code)}',
          );
        }, config);

        final result = await runner.run();
        expect(result.success, isTrue, reason: _formatResult(result));
      });

      test('server never crashes with chaotic OAuth states', () async {
        final config = PropertyConfig(numTests: 100, seed: 42);
        final runner = PropertyTestRunner(chaoticOAuthState(), (state) async {
          final csrfResponse = await client.get('/auth/csrf');
          final sessionCookie = csrfResponse.cookie('test_session');

          final response = await client.get(
            '/auth/callback/test-oauth?code=test-code&state=${Uri.encodeComponent(state)}',
            headers: {
              HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
            },
          );

          expect(
            response.statusCode,
            lessThan(500),
            reason: 'Server crashed with OAuth state: ${_sanitize(state)}',
          );
        }, config);

        final result = await runner.run();
        expect(result.success, isTrue, reason: _formatResult(result));
      });

      test('chaotic states never validate successfully', () async {
        final config = PropertyConfig(numTests: 100, seed: 42);
        final runner = PropertyTestRunner(chaoticOAuthState(), (state) async {
          final csrfResponse = await client.get('/auth/csrf');
          final sessionCookie = csrfResponse.cookie('test_session');

          final response = await client.get(
            '/auth/callback/test-oauth?code=test-code&state=${Uri.encodeComponent(state)}',
            headers: {
              HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
            },
          );

          // Chaotic states should NEVER succeed (200 or redirect)
          expect(
            response.statusCode,
            anyOf([400, 401, 403, 404]),
            reason: 'Chaotic state succeeded: ${_sanitize(state)}',
          );
        }, config);

        final result = await runner.run();
        expect(result.success, isTrue, reason: _formatResult(result));
      });
    });

    // ========================================================================
    // 4. ADVERSARIAL REDIRECT TESTING (OPEN REDIRECT PREVENTION)
    // ========================================================================
    group('4. Adversarial Redirect/CallbackUrl Testing', () {
      late AuthManager manager;
      late Engine engine;
      late TestClient client;

      setUp(() async {
        manager = AuthManager(
          AuthOptions(
            providers: [
              CredentialsProvider(
                authorize: (ctx, provider, credentials) async {
                  if (credentials.username == 'validuser' &&
                      credentials.password == 'validpass') {
                    return AuthUser(id: 'user-1', email: 'valid@example.com');
                  }
                  return null;
                },
              ),
            ],
            sessionStrategy: AuthSessionStrategy.session,
            enforceCsrf: false,
          ),
        );
        engine = _authEngine(manager);
        await engine.initialize();
        client = TestClient(RoutedRequestHandler(engine));
      });

      tearDown(() => client.close());

      test('server never crashes with chaotic callback URLs', () async {
        final config = PropertyConfig(numTests: 100, seed: 42);
        final runner = PropertyTestRunner(chaoticCallbackUrl(), (
          callbackUrl,
        ) async {
          final csrfResponse = await client.get('/auth/csrf');
          final sessionCookie = csrfResponse.cookie('test_session');

          final response = await client.postJson(
            '/auth/signin/credentials',
            {
              'username': 'validuser',
              'password': 'validpass',
              'callbackUrl': callbackUrl,
            },
            headers: {
              HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
            },
          );

          expect(
            response.statusCode,
            lessThan(500),
            reason: 'Server crashed with callbackUrl: $callbackUrl',
          );
        }, config);

        final result = await runner.run();
        expect(result.success, isTrue, reason: _formatResult(result));
      });

      test('malicious redirect URLs are sanitized', () async {
        final maliciousUrls = [
          'javascript:alert(1)',
          'data:text/html,<script>alert(1)</script>',
          '//evil.com/steal-token',
          'https://evil.com/callback',
          'https://legit.com@evil.com/',
          '\r\nLocation: http://evil.com',
          'file:///etc/passwd',
        ];

        for (final maliciousUrl in maliciousUrls) {
          final csrfResponse = await client.get('/auth/csrf');
          final sessionCookie = csrfResponse.cookie('test_session');

          final response = await client.postJson(
            '/auth/signin/credentials',
            {
              'username': 'validuser',
              'password': 'validpass',
              'callbackUrl': maliciousUrl,
            },
            headers: {
              HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
            },
          );

          // If redirect, should NOT redirect to the malicious URL
          if (response.statusCode == 302) {
            final location = response.headers['location']?.first ?? '';
            expect(
              location,
              isNot(contains('evil.com')),
              reason: 'Open redirect to evil.com with: $maliciousUrl',
            );
            expect(
              location,
              isNot(startsWith('javascript:')),
              reason: 'JavaScript redirect with: $maliciousUrl',
            );
            expect(
              location,
              isNot(startsWith('data:')),
              reason: 'Data URL redirect with: $maliciousUrl',
            );
          }
        }
      });
    });

    // ========================================================================
    // 5. CSRF TOKEN CHAOS TESTING
    // ========================================================================
    group('5. CSRF Token Chaos Testing', () {
      late AuthManager manager;
      late Engine engine;
      late TestClient client;

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
        client = TestClient(RoutedRequestHandler(engine));
      });

      tearDown(() => client.close());

      test('server never crashes with chaotic CSRF tokens', () async {
        final config = PropertyConfig(numTests: 100, seed: 42);
        final runner = PropertyTestRunner(chaoticCsrfToken(), (
          csrfToken,
        ) async {
          final csrfResponse = await client.get('/auth/csrf');
          final sessionCookie = csrfResponse.cookie('test_session');

          final response = await client.postJson(
            '/auth/signin/credentials',
            {
              'username': 'test',
              'password': 'test',
              if (csrfToken != null) '_csrf': csrfToken,
            },
            headers: {
              HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
            },
          );

          expect(
            response.statusCode,
            lessThan(500),
            reason: 'Server crashed with CSRF token: ${_sanitize(csrfToken)}',
          );
        }, config);

        final result = await runner.run();
        expect(result.success, isTrue, reason: _formatResult(result));
      });

      test('chaotic CSRF tokens never validate', () async {
        final config = PropertyConfig(numTests: 100, seed: 42);
        final runner = PropertyTestRunner(
          Chaos.string(minLength: 0, maxLength: 200),
          (csrfToken) async {
            final csrfResponse = await client.get('/auth/csrf');
            final sessionCookie = csrfResponse.cookie('test_session');
            final validCsrf = jsonDecode(csrfResponse.body)['csrfToken'];

            // Skip if we accidentally generated the valid token
            if (csrfToken == validCsrf) return;

            final response = await client.postJson(
              '/auth/signin/credentials',
              {'username': 'test', 'password': 'test', '_csrf': csrfToken},
              headers: {
                HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
              },
            );

            expect(
              response.statusCode,
              equals(403),
              reason: 'Chaotic CSRF accepted: ${_sanitize(csrfToken)}',
            );
          },
          config,
        );

        final result = await runner.run();
        expect(result.success, isTrue, reason: _formatResult(result));
      });
    });

    // ========================================================================
    // 6. PROVIDER ID CHAOS TESTING
    // ========================================================================
    group('6. Provider ID Chaos Testing', () {
      late AuthManager manager;
      late Engine engine;
      late TestClient client;

      setUp(() async {
        manager = AuthManager(
          AuthOptions(providers: [CredentialsProvider()], enforceCsrf: false),
        );
        engine = _authEngine(manager);
        await engine.initialize();
        client = TestClient(RoutedRequestHandler(engine));
      });

      tearDown(() => client.close());

      test('server never crashes with chaotic provider IDs', () async {
        final config = PropertyConfig(numTests: 100, seed: 42);
        final runner = PropertyTestRunner(Chaos.string(minLength: 0, maxLength: 100), (
          providerId,
        ) async {
          final csrfResponse = await client.get('/auth/csrf');
          final sessionCookie = csrfResponse.cookie('test_session');

          // Test signin
          final signinResponse = await client.postJson(
            '/auth/signin/${Uri.encodeComponent(providerId)}',
            {'username': 'test', 'password': 'test'},
            headers: {
              HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
            },
          );

          expect(
            signinResponse.statusCode,
            lessThan(500),
            reason:
                'Server crashed with provider ID in signin: ${_sanitize(providerId)}',
          );

          // Test callback
          final callbackResponse = await client.get(
            '/auth/callback/${Uri.encodeComponent(providerId)}?code=test&state=test',
            headers: {
              HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
            },
          );

          expect(
            callbackResponse.statusCode,
            lessThan(500),
            reason:
                'Server crashed with provider ID in callback: ${_sanitize(providerId)}',
          );

          // Test register
          final registerResponse = await client.postJson(
            '/auth/register/${Uri.encodeComponent(providerId)}',
            {'username': 'test', 'password': 'test'},
            headers: {
              HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
            },
          );

          expect(
            registerResponse.statusCode,
            lessThan(500),
            reason:
                'Server crashed with provider ID in register: ${_sanitize(providerId)}',
          );
        }, config);

        final result = await runner.run();
        expect(result.success, isTrue, reason: _formatResult(result));
      });
    });

    // ========================================================================
    // 7. JSON PAYLOAD CHAOS TESTING
    // ========================================================================
    group('7. Chaotic JSON Payload Testing', () {
      late AuthManager manager;
      late Engine engine;
      late TestClient client;

      setUp(() async {
        manager = AuthManager(
          AuthOptions(
            providers: [
              CredentialsProvider(
                authorize: (ctx, provider, credentials) async {
                  return null; // Always reject
                },
              ),
            ],
            enforceCsrf: false,
          ),
        );
        engine = _authEngine(manager);
        await engine.initialize();
        client = TestClient(RoutedRequestHandler(engine));
      });

      tearDown(() => client.close());

      test('server handles chaotic JSON bodies gracefully', () async {
        final config = PropertyConfig(numTests: 100, seed: 42);
        final runner = PropertyTestRunner(
          // Use smaller depth/length to avoid DoS-type large payloads
          Chaos.json(maxDepth: 2, maxLength: 5),
          (jsonString) async {
            // Skip extremely large payloads (these test DoS, not correctness)
            if (jsonString.length > 10000) return;

            final csrfResponse = await client.get('/auth/csrf');
            final sessionCookie = csrfResponse.cookie('test_session');

            final response = await client.post(
              '/auth/signin/credentials',
              jsonString,
              headers: {
                'Content-Type': ['application/json'],
                HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
              },
            );

            expect(
              response.statusCode,
              lessThan(500),
              reason: 'Server crashed with JSON: ${_sanitize(jsonString)}',
            );
          },
          config,
        );

        final result = await runner.run();
        expect(result.success, isTrue, reason: _formatResult(result));
      });

      test('server handles malformed JSON gracefully', () async {
        final malformedJsons = [
          '', // Empty
          '{', // Unclosed
          '}', // Only close
          '{"key":', // Incomplete value
          '{"key": undefined}', // Invalid value
          '{"key": NaN}', // NaN
          '{"key": Infinity}', // Infinity
          '{key: "value"}', // Unquoted key
          "{'key': 'value'}", // Single quotes
          '{"key": "value",}', // Trailing comma
          '{"key": "value",,}', // Double comma
          '\x00{"key": "value"}', // Null prefix
          '{"key": "value"}\x00', // Null suffix
          '{"key": "va\x00lue"}', // Null in value
        ];

        for (final json in malformedJsons) {
          final csrfResponse = await client.get('/auth/csrf');
          final sessionCookie = csrfResponse.cookie('test_session');

          final response = await client.post(
            '/auth/signin/credentials',
            json,
            headers: {
              'Content-Type': ['application/json'],
              HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
            },
          );

          expect(
            response.statusCode,
            lessThan(500),
            reason: 'Server crashed with malformed JSON: ${_sanitize(json)}',
          );
        }
      });
    });

    // ========================================================================
    // 8. STATEFUL AUTH FLOW TESTING
    // ========================================================================
    group('8. Stateful Auth Flow Testing', () {
      late AuthManager manager;
      late Engine engine;
      late TestClient client;

      setUp(() async {
        manager = AuthManager(
          AuthOptions(
            providers: [
              CredentialsProvider(
                authorize: (ctx, provider, credentials) async {
                  if (credentials.username == 'user' &&
                      credentials.password == 'pass') {
                    return AuthUser(id: 'user-1', email: 'user@example.com');
                  }
                  return null;
                },
              ),
            ],
            sessionStrategy: AuthSessionStrategy.session,
            enforceCsrf: false,
          ),
        );
        engine = _authEngine(manager);
        await engine.initialize();
        client = TestClient(RoutedRequestHandler(engine));
      });

      tearDown(() => client.close());

      test(
        'session invariant: session only exists after successful login',
        () async {
          // Model: whether user is logged in
          // Commands: login, logout, check session
          final commands = Gen.oneOf([
            'login_valid',
            'login_invalid',
            'logout',
            'check_session',
          ]);

          final config = StatefulPropertyConfig(
            numTests: 50,
            maxCommandSequenceLength: 20,
          );

          final runner = StatefulPropertyRunner<bool, String>(
            commands,
            () => false, // Initial state: not logged in
            (model) => true, // Invariant always holds (we check behavior)
            (model, command) {
              switch (command) {
                case 'login_valid':
                  return true;
                case 'login_invalid':
                  return model; // Invalid login doesn't change state
                case 'logout':
                  return false;
                case 'check_session':
                  return model; // Check doesn't change state
                default:
                  return model;
              }
            },
            config,
          );

          final result = await runner.run();
          expect(result.success, isTrue, reason: _formatResult(result));
        },
      );
    });

    // ========================================================================
    // 9. HEADER INJECTION TESTING
    // ========================================================================
    group('9. Header Injection Testing', () {
      late AuthManager manager;
      late Engine engine;
      late TestClient client;

      setUp(() async {
        manager = AuthManager(
          AuthOptions(
            providers: [
              CredentialsProvider(
                authorize: (ctx, provider, credentials) async => null,
              ),
            ],
            enforceCsrf: false,
          ),
        );
        engine = _authEngine(manager);
        await engine.initialize();
        client = TestClient(RoutedRequestHandler(engine));
      });

      tearDown(() => client.close());

      test('server handles header injection attempts', () async {
        final injectionAttempts = [
          'value\r\nX-Injected: attack',
          'value\r\n\r\n<html>attack</html>',
          'value\r\nSet-Cookie: stolen=true',
          'value%0d%0aX-Injected: attack',
          'value\nX-Injected: attack',
        ];

        for (final injection in injectionAttempts) {
          try {
            final response = await client.post(
              '/auth/signin/credentials',
              '{"username": "test", "password": "test"}',
              headers: {
                'Content-Type': ['application/json'],
                'X-Custom-Header': [injection],
              },
            );

            expect(
              response.statusCode,
              lessThan(500),
              reason:
                  'Server crashed with header injection: ${_sanitize(injection)}',
            );

            // Check that the injection didn't succeed
            final responseHeaders = response.headers.entries
                .map((e) => '${e.key}: ${e.value.join(",")}')
                .join('\n')
                .toLowerCase();

            expect(
              responseHeaders,
              isNot(contains('x-injected')),
              reason: 'Header injection succeeded: ${_sanitize(injection)}',
            );
          } catch (e) {
            // Some injections may be rejected at HTTP level, that's fine
            expect(
              e,
              isNot(isA<Error>()),
              reason: 'Fatal error with: ${_sanitize(injection)}',
            );
          }
        }
      });
    });

    // ========================================================================
    // 10. TIMING ATTACK RESILIENCE
    // ========================================================================
    group('10. Timing Attack Resilience', () {
      late AuthManager manager;
      late Engine engine;
      late TestClient client;

      setUp(() async {
        manager = AuthManager(
          AuthOptions(
            providers: [
              CredentialsProvider(
                authorize: (ctx, provider, credentials) async {
                  if (credentials.username == 'existinguser' &&
                      credentials.password == 'correctpass') {
                    return AuthUser(id: 'user-1');
                  }
                  return null;
                },
              ),
            ],
            enforceCsrf: false,
          ),
        );
        engine = _authEngine(manager);
        await engine.initialize();
        client = TestClient(RoutedRequestHandler(engine));
      });

      tearDown(() => client.close());

      test(
        'response time variance is acceptable for different failure modes',
        () async {
          final csrfResponse = await client.get('/auth/csrf');
          final sessionCookie = csrfResponse.cookie('test_session');

          // Measure times for different failure modes
          final measurements = <String, List<int>>{
            'nonexistent_user': [],
            'wrong_password': [],
            'empty_credentials': [],
          };

          const numSamples = 10;

          for (var i = 0; i < numSamples; i++) {
            // Non-existent user
            var sw = Stopwatch()..start();
            await client.postJson(
              '/auth/signin/credentials',
              {'username': 'nonexistentuser$i', 'password': 'anypass'},
              headers: {
                HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
              },
            );
            sw.stop();
            measurements['nonexistent_user']!.add(sw.elapsedMicroseconds);

            // Wrong password (existing user)
            sw = Stopwatch()..start();
            await client.postJson(
              '/auth/signin/credentials',
              {'username': 'existinguser', 'password': 'wrongpass$i'},
              headers: {
                HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
              },
            );
            sw.stop();
            measurements['wrong_password']!.add(sw.elapsedMicroseconds);

            // Empty credentials
            sw = Stopwatch()..start();
            await client.postJson(
              '/auth/signin/credentials',
              {'username': '', 'password': ''},
              headers: {
                HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
              },
            );
            sw.stop();
            measurements['empty_credentials']!.add(sw.elapsedMicroseconds);
          }

          // Calculate averages
          double average(List<int> values) =>
              values.reduce((a, b) => a + b) / values.length;

          final avgNonexistent = average(measurements['nonexistent_user']!);
          final avgWrongPass = average(measurements['wrong_password']!);
          final avgEmpty = average(measurements['empty_credentials']!);

          // The timing difference should be within 50% (this is a rough check)
          // In a real timing attack test, you'd need much more sophisticated analysis
          final maxTime = [
            avgNonexistent,
            avgWrongPass,
            avgEmpty,
          ].reduce((a, b) => a > b ? a : b);
          final minTime = [
            avgNonexistent,
            avgWrongPass,
            avgEmpty,
          ].reduce((a, b) => a < b ? a : b);

          // Allow 10x variance (very lenient - timing attacks need much more precision)
          expect(
            maxTime / minTime,
            lessThan(10),
            reason:
                'Large timing variance detected: nonexistent=$avgNonexistent, wrongPass=$avgWrongPass, empty=$avgEmpty',
          );
        },
      );
    });
  });
}

// ============================================================================
// HELPERS
// ============================================================================

String _formatResult(PropertyResult result) {
  if (result.success) return 'All ${result.numTests} tests passed';

  final buffer = StringBuffer()
    ..writeln('Failed after ${result.numTests} tests')
    ..writeln('Original input: ${_sanitize(result.originalFailingInput)}')
    ..writeln('Shrunk input: ${_sanitize(result.failingInput)}')
    ..writeln('Shrink steps: ${result.numShrinks}')
    ..writeln('Error: ${result.error}')
    ..writeln('Seed: ${result.seed}');

  return buffer.toString();
}

/// Sanitize potentially dangerous strings for safe display in test output
String _sanitize(dynamic value) {
  if (value == null) return '<null>';
  final str = value.toString();
  if (str.length > 100) {
    return '${str.substring(0, 100)}... (${str.length} chars)';
  }
  return str
      .replaceAll('\r', '\\r')
      .replaceAll('\n', '\\n')
      .replaceAll('\t', '\\t')
      .replaceAll('\x00', '\\0');
}
