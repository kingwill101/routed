import 'dart:convert';
import 'dart:io';

import 'package:routed_auth/routed_auth.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import '../test_engine.dart';

SessionConfig _sessionConfig() {
  final key = base64.encode(List<int>.generate(32, (index) => index + 1));
  return SessionConfig.cookie(
    appKey: 'base64:$key',
    cookieName: 'test_session',
    options: SessionOptions(
      secure: false,
      httpOnly: true,
      sameSite: SameSite.lax,
    ),
  );
}

Engine _authEngine(AuthManager manager) {
  final engine = testEngine(
    config: EngineConfig(
      security: const EngineSecurityFeatures(csrfProtection: false),
    ),
    providers: [RoutedSessionsProvider(_sessionConfig())],
  );
  engine.addGlobalMiddleware(sessionMiddleware());
  engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());
  AuthRoutes(manager).register(engine.defaultRouter);
  return engine;
}

String _cookieHeader(Cookie cookie) => '${cookie.name}=${cookie.value}';

Future<({String csrf, Cookie session})> _csrf(TestClient client) async {
  final response = await client.get('/auth/csrf');
  response.assertStatus(HttpStatus.ok);
  return (
    csrf: response.json()['csrfToken'] as String,
    session: response.cookie('test_session')!,
  );
}

Argon2idPasswordHasher _testHasher() =>
    Argon2idPasswordHasher(iterations: 1, memoryKiB: 8, derivedKeyLength: 16);

final class _RecordingLimiter implements AuthRateLimiter<EngineContext> {
  _RecordingLimiter(this.events);

  final List<String> events;
  AuthRateLimitRequest<EngineContext>? lastRequest;

  @override
  AuthRateLimitDecision check(AuthRateLimitRequest<EngineContext> request) {
    events.add('rate');
    lastRequest = request;
    return const AuthRateLimitDecision.allow();
  }
}

final class _CaptchaVerifier implements AuthCaptchaVerifier<EngineContext> {
  _CaptchaVerifier(this.events);

  final List<String> events;
  final List<String> tokens = <String>[];

  @override
  AuthCaptchaVerificationResult verify(
    AuthCaptchaVerificationRequest<EngineContext> request,
  ) {
    events.add('captcha');
    tokens.add(request.token);
    return const AuthCaptchaVerificationResult.accepted();
  }
}

final class _BreachedLookup
    implements AuthBreachedPasswordLookup<EngineContext> {
  _BreachedLookup(this.events) : breached = true;

  final List<String> events;
  bool breached;
  final List<String> passwords = <String>[];

  @override
  AuthBreachedPasswordCheckResult check(
    AuthBreachedPasswordCheckRequest<EngineContext> request,
  ) {
    events.add('breached');
    passwords.add(request.password);
    return breached
        ? const AuthBreachedPasswordCheckResult.breached()
        : const AuthBreachedPasswordCheckResult.allowed();
  }
}

void main() {
  test(
    'captcha runs after the existing rate limit and before credentials',
    () async {
      final events = <String>[];
      final limiter = _RecordingLimiter(events);
      final verifier = _CaptchaVerifier(events);
      final user = AuthUser(id: 'user-1', email: 'user@example.com');
      final provider = CredentialsProvider(
        authorize: (_, _, credentials) {
          events.add('provider');
          expect(credentials.attributes.containsKey('captchaToken'), isFalse);
          return user;
        },
      );
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [provider],
          rateLimiter: limiter,
          plugins: [CaptchaPlugin<EngineContext>(verifier: verifier)],
        ),
      );
      final engine = _authEngine(manager);
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);

      final csrf = await _csrf(client);
      final headers = <String, List<String>>{
        HttpHeaders.cookieHeader: [_cookieHeader(csrf.session)],
      };
      final missing = await client.postJson(
        '/auth/signin/credentials',
        <String, dynamic>{
          'email': user.email,
          'password': 'correct-password-123',
          '_csrf': csrf.csrf,
        },
        headers: headers,
      );
      missing.assertStatus(HttpStatus.unauthorized);
      expect(missing.json()['error'], authCaptchaFailedErrorCode);
      expect(events, ['rate']);

      events.clear();
      final accepted = await client
          .postJson('/auth/signin/credentials', <String, dynamic>{
            'email': user.email,
            'password': 'correct-password-123',
            'captchaToken': 'vendor-token-secret',
            '_csrf': csrf.csrf,
          }, headers: headers);
      accepted.assertStatus(HttpStatus.ok);
      expect(events, ['rate', 'captcha', 'provider']);
      expect(accepted.body, isNot(contains('vendor-token-secret')));
      expect(accepted.body, isNot(contains('correct-password-123')));
      expect(verifier.tokens, ['vendor-token-secret']);
    },
  );

  test('breached registration rejects before the provider callback', () async {
    final events = <String>[];
    final limiter = _RecordingLimiter(events);
    var registrations = 0;
    final provider = CredentialsProvider(
      register: (_, _, credentials) {
        registrations += 1;
        return AuthUser(id: 'new-user', email: credentials.email);
      },
    );
    final lookup = _BreachedLookup(events);
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        providers: [provider],
        rateLimiter: limiter,
        plugins: [BreachedPasswordPlugin<EngineContext>(lookup: lookup)],
      ),
    );
    final engine = _authEngine(manager);
    await engine.initialize();
    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(client.close);

    final csrf = await _csrf(client);
    final response = await client.postJson(
      '/auth/register/credentials',
      <String, dynamic>{
        'email': 'new@example.com',
        'password': 'known-breached-password',
        '_csrf': csrf.csrf,
      },
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(csrf.session)],
      },
    );

    response.assertStatus(HttpStatus.unauthorized);
    expect(response.json()['error'], authBreachedPasswordRejectedErrorCode);
    expect(events, ['rate', 'breached']);
    expect(registrations, 0);
    expect(response.body, isNot(contains('known-breached-password')));
  });

  test('password reset checks before consuming a valid reset token', () async {
    final store = InMemoryAuthStore();
    final hasher = _testHasher();
    final user = await authorizeCredentialsRegistration(
      store: store,
      passwordHasher: hasher,
      provider: CredentialsProvider(),
      context: Object(),
      credentials: AuthCredentials(
        email: 'reset@example.com',
        password: 'old-password-123',
      ),
    );
    await store.markEmailVerified(user!.id);
    AuthPasswordResetRequest<EngineContext>? delivery;
    final events = <String>[];
    final lookup = _BreachedLookup(events);
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: store,
        storeMode: AuthStoreMode.ephemeral,
        passwordHasher: hasher,
        providers: [CredentialsProvider()],
        plugins: [BreachedPasswordPlugin<EngineContext>(lookup: lookup)],
        passwordResetSender: (request) => delivery = request,
      ),
    );
    final engine = _authEngine(manager);
    await engine.initialize();
    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(client.close);

    final csrf = await _csrf(client);
    final headers = <String, List<String>>{
      HttpHeaders.cookieHeader: [_cookieHeader(csrf.session)],
    };
    final requested = await client.postJson('/auth/password-reset/request', {
      'email': user.email,
      '_csrf': csrf.csrf,
    }, headers: headers);
    requested.assertStatus(HttpStatus.accepted);
    final resetToken = delivery!.token;

    final rejected = await client.postJson('/auth/password-reset/confirm', {
      'token': resetToken,
      'newPassword': 'known-breached-password',
      '_csrf': csrf.csrf,
    }, headers: headers);
    rejected.assertStatus(HttpStatus.unauthorized);
    expect(rejected.json()['error'], authBreachedPasswordRejectedErrorCode);
    expect(rejected.body, isNot(contains(resetToken)));
    expect(lookup.passwords, ['known-breached-password']);

    lookup.breached = false;
    final accepted = await client.postJson('/auth/password-reset/confirm', {
      'token': resetToken,
      'newPassword': 'new-password-456',
      '_csrf': csrf.csrf,
    }, headers: headers);
    accepted.assertStatus(HttpStatus.ok);
    expect(accepted.json()['status'], 'password_reset_complete');
  });

  test(
    'password-change lookup runs only after current-password reauth',
    () async {
      final store = InMemoryAuthStore();
      final hasher = _testHasher();
      final user = await authorizeCredentialsRegistration(
        store: store,
        passwordHasher: hasher,
        provider: CredentialsProvider(),
        context: Object(),
        credentials: AuthCredentials(
          email: 'change@example.com',
          password: 'old-password-123',
        ),
      );
      final events = <String>[];
      final lookup = _BreachedLookup(events);
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          passwordHasher: hasher,
          providers: [CredentialsProvider()],
          plugins: [BreachedPasswordPlugin<EngineContext>(lookup: lookup)],
        ),
      );
      final engine = _authEngine(manager);
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);

      final csrf = await _csrf(client);
      final initialHeaders = <String, List<String>>{
        HttpHeaders.cookieHeader: [_cookieHeader(csrf.session)],
      };
      final signIn = await client.postJson('/auth/signin/credentials', {
        'email': user!.email,
        'password': 'old-password-123',
        '_csrf': csrf.csrf,
      }, headers: initialHeaders);
      signIn.assertStatus(HttpStatus.ok);
      final session = signIn.cookie('test_session')!;

      final wrongCurrent = await client.postJson(
        '/auth/password/change',
        {
          'identifier': user.email,
          'currentPassword': 'wrong-password-123',
          'newPassword': 'known-breached-password',
          '_csrf': csrf.csrf,
        },
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(session)],
        },
      );
      wrongCurrent.assertStatus(HttpStatus.unauthorized);
      expect(wrongCurrent.json()['error'], 'invalid_current_password');
      expect(events, isEmpty);

      final rightCurrent = await client.postJson(
        '/auth/password/change',
        {
          'identifier': user.email,
          'currentPassword': 'old-password-123',
          'newPassword': 'known-breached-password',
          '_csrf': csrf.csrf,
        },
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(session)],
        },
      );
      rightCurrent.assertStatus(HttpStatus.unauthorized);
      expect(
        rightCurrent.json()['error'],
        authBreachedPasswordRejectedErrorCode,
      );
      expect(events, ['breached']);
      expect(rightCurrent.body, isNot(contains('known-breached-password')));
    },
  );
}
