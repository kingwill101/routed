import 'dart:convert';
import 'dart:io';

import 'package:routed_core/routed_core.dart';
import 'package:routed_auth/routed_auth.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import '../test_engine.dart';

SessionConfig _sessionConfig() {
  final key = base64.encode(List<int>.generate(32, (i) => i + 1));
  return SessionConfig.cookie(
    appKey: 'base64:$key',
    cookieName: 'test_session',
    options: SessionOptions(
      path: '/',
      secure: false,
      httpOnly: true,
      sameSite: SameSite.lax,
    ),
  );
}

Engine _authEngine(AuthManager manager) {
  final sessionConfig = _sessionConfig();
  final engine = testEngine(
    config: EngineConfig(
      security: const EngineSecurityFeatures(csrfProtection: false),
    ),
    providers: [RoutedSessionsProvider(sessionConfig)],
  );
  engine.addGlobalMiddleware(sessionMiddleware());
  AuthRoutes(manager).register(engine.defaultRouter);
  return engine;
}

String _cookieHeader(Cookie cookie) => '${cookie.name}=${cookie.value}';

final class _BlockingAuthLimiter implements AuthRateLimiter<EngineContext> {
  AuthRateLimitRequest<EngineContext>? lastRequest;

  @override
  AuthRateLimitDecision check(AuthRateLimitRequest<EngineContext> request) {
    lastRequest = request;
    return const AuthRateLimitDecision.block(retryAfter: Duration(seconds: 17));
  }
}

void main() {
  test(
    'blocks unverified and disabled users before issuing a session',
    () async {
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            CredentialsProvider(
              authorize: (_, _, credentials) async {
                if (credentials.email == 'unverified@example.com') {
                  return AuthUser(id: 'unverified', email: credentials.email);
                }
                return AuthUser(
                  id: 'disabled',
                  email: credentials.email,
                  attributes: const {'disabled': true},
                );
              },
            ),
          ],
          requireVerifiedEmail: true,
          enforceCsrf: false,
        ),
      );

      final engine = _authEngine(manager);
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      final unverified = await client.postJson(
        '/auth/signin/credentials',
        <String, dynamic>{
          'email': 'unverified@example.com',
          'password': 'secret',
        },
      );
      unverified.assertStatus(HttpStatus.unauthorized);
      expect(unverified.json()['error'], equals('email_verification_required'));

      final disabled = await client.postJson(
        '/auth/signin/credentials',
        <String, dynamic>{
          'email': 'disabled@example.com',
          'password': 'secret',
        },
      );
      disabled.assertStatus(HttpStatus.unauthorized);
      expect(disabled.json()['error'], equals('account_unavailable'));
    },
  );

  test(
    'verified provider results synchronize existing account state',
    () async {
      final store = InMemoryAuthStore();
      await store.upsert(
        const AuthAccountState(userId: 'verified-user', emailVerified: false),
      );
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            CredentialsProvider(
              authorize: (_, _, credentials) => AuthUser(
                id: 'verified-user',
                email: credentials.email,
                attributes: const {'emailVerified': true},
              ),
            ),
          ],
          accountPolicy: AuthAccountPolicy.production,
          enforceCsrf: false,
        ),
      );
      final engine = _authEngine(manager);
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);

      final response = await client.postJson('/auth/signin/credentials', {
        'email': 'verified@example.com',
        'password': 'secret',
      });

      expect(response.statusCode, HttpStatus.ok, reason: response.body);
      expect((await store.find('verified-user'))?.emailVerified, isTrue);
    },
  );

  test('failed username sign-ins update the owning account lockout', () async {
    final store = InMemoryAuthStore();
    final hasher = Argon2idPasswordHasher(
      iterations: 1,
      memoryKiB: 8,
      derivedKeyLength: 16,
    );
    final now = DateTime.now().toUtc();
    await store.credentials.register(
      AuthUser(id: 'user-1'),
      AuthPasswordCredential(
        id: 'credential-1',
        userId: 'user-1',
        identifier: 'alice',
        passwordHash: hasher.hash('correct-password'),
        createdAt: now,
        updatedAt: now,
      ),
    );
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: store,
        storeMode: AuthStoreMode.ephemeral,
        providers: [CredentialsProvider()],
        passwordHasher: hasher,
        accountPolicy: const AuthAccountPolicy(maxLoginAttempts: 1),
        enforceCsrf: false,
      ),
    );
    final engine = _authEngine(manager);
    await engine.initialize();
    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(() async => await client.close());

    final response = await client.postJson(
      '/auth/signin/credentials',
      <String, dynamic>{'username': 'alice', 'password': 'wrong-password'},
    );

    response.assertStatus(HttpStatus.unauthorized);
    expect((await store.find('user-1'))?.failedLoginAttempts, equals(1));
    expect((await store.find('user-1'))?.isLocked(), isTrue);
  });

  test('rejects credential requests from an untrusted origin', () async {
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        providers: [CredentialsProvider()],
        enforceCsrf: false,
      ),
    );

    final engine = _authEngine(manager);
    await engine.initialize();

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(() async => await client.close());

    final response = await client.postJson(
      '/auth/signin/credentials',
      <String, dynamic>{'username': 'alice', 'password': 'secret'},
      headers: <String, List<String>>{
        'Origin': ['https://evil.example'],
      },
    );

    response.assertStatus(HttpStatus.forbidden);
    expect(response.json()['error'], equals('invalid_origin'));
  });

  test('rejects origins that hide user-info before a trusted host', () async {
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        providers: [CredentialsProvider()],
        enforceCsrf: false,
      ),
    );

    final engine = _authEngine(manager);
    await engine.initialize();

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(() async => await client.close());

    final response = await client.postJson(
      '/auth/signin/credentials',
      <String, dynamic>{'username': 'alice', 'password': 'secret'},
      headers: <String, List<String>>{
        'Origin': ['http://attacker@localhost'],
      },
    );

    response.assertStatus(HttpStatus.forbidden);
    expect(response.json()['error'], equals('invalid_origin'));
  });

  test('allows an explicitly configured browser origin', () async {
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        providers: [CredentialsProvider()],
        enforceCsrf: false,
        browserProtection: const AuthBrowserProtectionOptions(
          allowedOrigins: ['https://app.example'],
        ),
      ),
    );

    final engine = _authEngine(manager);
    await engine.initialize();

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(() async => await client.close());

    final response = await client.postJson(
      '/auth/signin/credentials',
      <String, dynamic>{'username': 'alice', 'password': 'secret'},
      headers: <String, List<String>>{
        'Origin': ['https://app.example'],
      },
    );

    response.assertStatus(HttpStatus.unauthorized);
    expect(response.json()['error'], equals('invalid_credentials'));
  });

  test('rejects Fetch Metadata cross-site credential requests', () async {
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        providers: [CredentialsProvider()],
        enforceCsrf: false,
      ),
    );

    final engine = _authEngine(manager);
    await engine.initialize();

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(() async => await client.close());

    final response = await client.postJson(
      '/auth/signin/credentials',
      <String, dynamic>{'username': 'alice', 'password': 'secret'},
      headers: <String, List<String>>{
        'Sec-Fetch-Site': ['cross-site'],
      },
    );

    response.assertStatus(HttpStatus.forbidden);
    expect(response.json()['error'], equals('cross_site_request'));
  });

  test(
    'explicit CSRF opt-out does not reject a request for CSRF absence',
    () async {
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [CredentialsProvider()],
          enforceCsrf: false,
        ),
      );

      final engine = _authEngine(manager);
      await engine.initialize();

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      final response = await client.postJson(
        '/auth/signin/credentials',
        <String, dynamic>{'username': 'alice', 'password': 'secret'},
      );

      response.assertStatus(HttpStatus.unauthorized);
      expect(response.json()['error'], equals('invalid_credentials'));
    },
  );

  test(
    'credentials sign-in is rate limited before password processing',
    () async {
      final limiter = _BlockingAuthLimiter();
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [CredentialsProvider()],
          enforceCsrf: false,
          rateLimiter: limiter,
        ),
      );

      final engine = _authEngine(manager);
      await engine.initialize();

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      final response = await client.postJson(
        '/auth/signin/credentials',
        <String, dynamic>{
          'username': 'alice',
          'password': 'must-not-reach-the-limiter',
        },
      );

      response.assertStatus(HttpStatus.tooManyRequests);
      expect(response.json()['error'], equals('rate_limited'));
      expect(response.headers[HttpHeaders.retryAfterHeader], contains('17'));
      expect(
        limiter.lastRequest?.operation,
        AuthRateLimitOperation.core(AuthRateLimitAction.signIn),
      );
      expect(limiter.lastRequest?.providerId, equals('credentials'));
      expect(limiter.lastRequest?.identifier, equals('alice'));
    },
  );

  test(
    'built-in registration rejects weak passwords before persistence',
    () async {
      final store = InMemoryAuthStore();
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          providers: [CredentialsProvider()],
          enforceCsrf: false,
        ),
      );

      final engine = _authEngine(manager);
      await engine.initialize();

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      final response = await client.postJson(
        '/auth/register/credentials',
        <String, dynamic>{'email': 'weak@example.com', 'password': 'short'},
      );

      response.assertStatus(HttpStatus.unauthorized);
      expect(response.json()['error'], equals('registration_failed'));
      expect(await store.users.findByEmail('weak@example.com'), isNull);
    },
  );

  test('GET sign-in for credentials is rejected', () async {
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        providers: [CredentialsProvider()],
        enforceCsrf: false,
      ),
    );

    final engine = _authEngine(manager);
    await engine.initialize();

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(() async => await client.close());

    final response = await client.get('/auth/signin/credentials');
    response.assertStatus(HttpStatus.methodNotAllowed);
    expect(response.json()['error'], equals('method_not_allowed'));
  });

  test(
    'unexpected credential failures do not expose exception details',
    () async {
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            CredentialsProvider(
              authorize: (_, _, _) async {
                throw StateError('/srv/secrets/auth-production.key');
              },
            ),
          ],
          enforceCsrf: false,
        ),
      );

      final engine = _authEngine(manager);
      await engine.initialize();

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      final response = await client.postJson(
        '/auth/signin/credentials',
        <String, dynamic>{'username': 'alice', 'password': 'secret'},
      );

      response.assertStatus(HttpStatus.internalServerError);
      expect(response.body, isNot(contains('auth-production.key')));
      expect(response.body, isNot(contains('/srv/secrets')));
      expect(response.body, contains('unexpected error'));
    },
  );

  test('callbackUrl sanitization ignores external redirects', () async {
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        providers: [
          OAuthProvider<Map<String, dynamic>>(
            id: 'oauth',
            name: 'OAuth',
            clientId: 'client-id',
            clientSecret: 'client-secret',
            authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
            tokenEndpoint: Uri.parse('https://auth.test/token'),
            redirectUri: 'https://app.test/auth/callback/oauth',
            profile: (profile) => AuthUser(id: 'user'),
          ),
        ],
      ),
    );

    final engine = _authEngine(manager);
    await engine.initialize();

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(() async => await client.close());

    final response = await client.get(
      '/auth/signin/oauth?callbackUrl=https://evil.test',
    );
    response.assertStatus(HttpStatus.movedTemporarily);
    final location = response.headers[HttpHeaders.locationHeader]!.first;
    final uri = Uri.parse(location);
    expect(uri.queryParameters.containsKey('callbackUrl'), isFalse);
  });

  test(
    'OAuth callback is bound to the browser that started the flow',
    () async {
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            OAuthProvider<Map<String, dynamic>>(
              id: 'oauth',
              name: 'OAuth',
              clientId: 'client-id',
              clientSecret: 'client-secret',
              authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
              tokenEndpoint: Uri.parse('https://auth.test/token'),
              redirectUri: 'https://app.test/auth/callback/oauth',
              profile: (profile) => AuthUser(id: 'attacker-user'),
            ),
          ],
        ),
      );

      final engine = _authEngine(manager);
      await engine.initialize();

      final attacker = TestClient(RoutedRequestHandler(engine));
      final victim = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async {
        await attacker.close();
        await victim.close();
      });

      final start = await attacker.get('/auth/signin/oauth');
      start.assertStatus(HttpStatus.movedTemporarily);
      final location = Uri.parse(
        start.headers[HttpHeaders.locationHeader]!.first,
      );
      final state = location.queryParameters['state'];
      expect(state, isNotNull);
      final stateCookie = (start.headers[HttpHeaders.setCookieHeader] ?? [])
          .map(Cookie.fromSetCookieValue)
          .firstWhere(
            (cookie) => cookie.name.startsWith('routed_oauth_state_'),
          );
      expect(stateCookie.secure, isTrue);
      expect(stateCookie.sameSite, SameSite.none);

      final callback = await victim.get(
        '/auth/callback/oauth?code=attacker-code&state=$state',
      );

      callback.assertStatus(HttpStatus.unauthorized);
      expect(callback.json()['error'], equals('invalid_state'));
      expect(stateCookie.value, equals(state));
    },
  );

  test(
    'email callback is bound to the browser that requested the link',
    () async {
      late AuthEmailRequest request;
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            EmailProvider(
              sendVerificationRequest: (_, _, sent) async {
                request = sent;
              },
            ),
          ],
          enforceCsrf: false,
        ),
      );

      final engine = _authEngine(manager);
      await engine.initialize();

      final attacker = TestClient(RoutedRequestHandler(engine));
      final victim = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async {
        await attacker.close();
        await victim.close();
      });

      final start = await attacker.postJson('/auth/signin/email', {
        'email': 'attacker@example.com',
      });
      start.assertStatus(HttpStatus.ok);

      final callback = await victim.get(
        '/auth/callback/email?token=${request.token}&email=${request.email}',
      );

      callback.assertStatus(HttpStatus.unauthorized);
      expect(callback.json()['error'], equals('invalid_token'));
    },
  );

  test('unknown providers return not found responses', () async {
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        providers: [CredentialsProvider()],
        enforceCsrf: false,
      ),
    );

    final engine = _authEngine(manager);
    await engine.initialize();

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(() async => await client.close());

    final signIn = await client.postJson(
      '/auth/signin/missing',
      <String, dynamic>{},
    );
    signIn.assertStatus(HttpStatus.notFound);
    expect(signIn.json()['error'], equals('unknown_provider'));

    final register = await client.postJson(
      '/auth/register/missing',
      <String, dynamic>{},
    );
    register.assertStatus(HttpStatus.notFound);
    expect(register.json()['error'], equals('unknown_provider'));

    final callback = await client.get('/auth/callback/missing');
    callback.assertStatus(HttpStatus.notFound);
    expect(callback.json()['error'], equals('unknown_provider'));
  });

  test('rejects missing OAuth callback code', () async {
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        providers: [
          OAuthProvider<Map<String, dynamic>>(
            id: 'oauth',
            name: 'OAuth',
            clientId: 'client-id',
            clientSecret: 'client-secret',
            authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
            tokenEndpoint: Uri.parse('https://auth.test/token'),
            redirectUri: 'https://app.test/auth/callback/oauth',
            profile: (profile) => AuthUser(id: 'user'),
          ),
        ],
      ),
    );

    final engine = _authEngine(manager);
    await engine.initialize();

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(() async => await client.close());

    final response = await client.get('/auth/callback/oauth');
    response.assertStatus(HttpStatus.badRequest);
    expect(response.json()['error'], equals('missing_code'));
  });

  test('rejects missing email verification tokens', () async {
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        providers: [EmailProvider(sendVerificationRequest: (_, _, _) async {})],
        enforceCsrf: false,
      ),
    );

    final engine = _authEngine(manager);
    await engine.initialize();

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(() async => await client.close());

    final response = await client.get('/auth/callback/email?email=test');
    response.assertStatus(HttpStatus.badRequest);
    expect(response.json()['error'], equals('missing_token'));
  });

  test('register rejects unsupported providers', () async {
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        providers: [EmailProvider(sendVerificationRequest: (_, _, _) async {})],
        enforceCsrf: false,
      ),
    );

    final engine = _authEngine(manager);
    await engine.initialize();

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(() async => await client.close());

    final response = await client.postJson(
      '/auth/register/email',
      <String, dynamic>{},
    );
    response.assertStatus(HttpStatus.badRequest);
    expect(response.json()['error'], equals('unsupported_provider'));
  });

  test('rejects invalid CSRF tokens on sign-in', () async {
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        providers: [CredentialsProvider()],
        enforceCsrf: true,
      ),
    );

    final engine = _authEngine(manager);
    await engine.initialize();

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(() async => await client.close());

    final csrfResponse = await client.get('/auth/csrf');
    final sessionCookie = csrfResponse.cookie('test_session');
    expect(sessionCookie, isNotNull);

    final signIn = await client.postJson(
      '/auth/signin/credentials',
      {'email': 'user@example.com', 'password': 'secret', '_csrf': 'bad'},
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
      },
    );
    signIn.assertStatus(HttpStatus.forbidden);
    expect(signIn.json()['error'], equals('invalid_csrf'));
  });

  test('signout clears JWT cookies', () async {
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        providers: [CredentialsProvider()],
        sessionStrategy: AuthSessionStrategy.jwt,
        enforceCsrf: false,
      ),
    );

    final engine = _authEngine(manager);
    await engine.initialize();

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(() async => await client.close());

    final signOut = await client.postJson('/auth/signout', <String, dynamic>{});
    signOut.assertStatus(HttpStatus.ok);
    final cookie = signOut.cookie(manager.options.jwtOptions.cookieName);
    expect(cookie, isNotNull);
    expect(cookie!.maxAge, equals(0));
  });
}
