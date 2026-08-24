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

void main() {
  test(
    'password reset routes do not enumerate users and are single-use',
    () async {
      final store = InMemoryAuthStore();
      final hasher = _testHasher();
      final created = await authorizeCredentialsRegistration(
        store: store,
        passwordHasher: hasher,
        provider: CredentialsProvider(),
        context: Object(),
        credentials: AuthCredentials(
          email: 'user@example.com',
          password: 'old-password-123',
        ),
      );
      expect(created, isNotNull);
      await store.users.update(
        AuthUser(
          id: created!.id,
          email: created.email,
          attributes: const {'secret': 'must-not-be-delivered'},
        ),
      );
      final trustedDeviceStore = InMemoryAuthTwoFactorTrustedDeviceStore();
      final resetNow = DateTime.now().toUtc();
      trustedDeviceStore.create(
        AuthTwoFactorTrustedDeviceRecord(
          id: 'trusted-reset-1',
          userId: created.id,
          tokenHash: hashOpaqueToken('old-reset-device'),
          createdAt: resetNow,
          expiresAt: resetNow.add(const Duration(days: 30)),
        ),
      );

      AuthPasswordResetRequest<EngineContext>? delivered;
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          providers: [CredentialsProvider()],
          passwordHasher: hasher,
          plugins: [
            TwoFactorPlugin<EngineContext>(
              backend: InMemoryAuthTwoFactorBackend(
                trustedDeviceStore: trustedDeviceStore,
              ),
              secretProtector: const PlaintextAuthTwoFactorSecretProtector(),
            ),
          ],
          passwordResetSender: (request) => delivered = request,
        ),
      );
      final engine = _authEngine(manager);
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => client.close());

      final csrf = await _csrf(client);
      final headers = <String, List<String>>{
        HttpHeaders.cookieHeader: [_cookieHeader(csrf.session)],
      };
      final known = await client.postJson('/auth/password-reset/request', {
        'email': 'USER@example.com',
        '_csrf': csrf.csrf,
      }, headers: headers);
      final unknown = await client.postJson('/auth/password-reset/request', {
        'email': 'missing@example.com',
        '_csrf': csrf.csrf,
      }, headers: headers);

      known.assertStatus(HttpStatus.accepted);
      unknown.assertStatus(HttpStatus.accepted);
      expect(known.body, equals(unknown.body));
      expect(known.json()['status'], equals('password_reset_requested'));
      expect(delivered, isNotNull);
      expect(delivered!.user.attributes, isEmpty);
      expect(delivered!.token, isNotEmpty);
      expect(delivered!.expiresAt.isAfter(DateTime.now().toUtc()), isTrue);

      final confirmed = await client.postJson('/auth/password-reset/confirm', {
        'token': delivered!.token,
        'newPassword': 'new-password-456',
        '_csrf': csrf.csrf,
      }, headers: headers);
      confirmed.assertStatus(HttpStatus.ok);
      expect(confirmed.json()['status'], equals('password_reset_complete'));
      expect(
        trustedDeviceStore.findActive(
          created.id,
          hashOpaqueToken('old-reset-device'),
          now: DateTime.now().toUtc(),
        ),
        isNull,
      );

      final replay = await client.postJson('/auth/password-reset/confirm', {
        'token': delivered!.token,
        'newPassword': 'new-password-789',
        '_csrf': csrf.csrf,
      }, headers: headers);
      replay.assertStatus(HttpStatus.unauthorized);
      expect(replay.json()['error'], equals('invalid_password_reset_token'));

      expect(
        await authorizeCredentialsSignIn(
          store: store,
          passwordHasher: hasher,
          provider: CredentialsProvider(),
          context: Object(),
          credentials: AuthCredentials(
            email: 'user@example.com',
            password: 'old-password-123',
          ),
        ),
        isNull,
      );
      expect(
        (await authorizeCredentialsSignIn(
          store: store,
          passwordHasher: hasher,
          provider: CredentialsProvider(),
          context: Object(),
          credentials: AuthCredentials(
            email: 'user@example.com',
            password: 'new-password-456',
          ),
        ))?.id,
        equals(created.id),
      );
    },
  );

  test(
    'password reset routes enforce browser protection and rate limits',
    () async {
      final limiter = _BlockingLimiter();
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [CredentialsProvider()],
          passwordResetSender: (_) {},
          rateLimiter: limiter,
        ),
      );
      final engine = _authEngine(manager);
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => client.close());

      final csrf = await _csrf(client);
      final headers = <String, List<String>>{
        HttpHeaders.cookieHeader: [_cookieHeader(csrf.session)],
        'Origin': ['https://evil.example'],
      };
      final originRejected = await client.postJson(
        '/auth/password-reset/request',
        {'email': 'user@example.com', '_csrf': csrf.csrf},
        headers: headers,
      );
      originRejected.assertStatus(HttpStatus.forbidden);
      expect(originRejected.json()['error'], equals('invalid_origin'));
      expect(limiter.lastRequest, isNull);

      final allowed = await client.postJson(
        '/auth/password-reset/request',
        {'email': 'user@example.com', '_csrf': csrf.csrf},
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(csrf.session)],
        },
      );
      allowed.assertStatus(HttpStatus.tooManyRequests);
      expect(allowed.json()['error'], equals('rate_limited'));
      expect(
        limiter.lastRequest?.operation,
        equals(
          AuthRateLimitOperation.core(AuthRateLimitAction.passwordResetRequest),
        ),
      );
      expect(limiter.lastRequest?.providerId, equals('password-reset'));
    },
  );

  test('password reset policy blocks disabled and unverified accounts without '
      'consuming an existing token', () async {
    final store = InMemoryAuthStore();
    final hasher = _testHasher();
    final user = await authorizeCredentialsRegistration(
      store: store,
      passwordHasher: hasher,
      provider: CredentialsProvider(),
      context: Object(),
      credentials: AuthCredentials(
        email: 'policy@example.com',
        password: 'old-password-123',
      ),
    );
    expect(user, isNotNull);
    await store.markEmailVerified(user!.id);

    final deliveries = <AuthPasswordResetRequest<EngineContext>>[];
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: store,
        storeMode: AuthStoreMode.ephemeral,
        providers: [CredentialsProvider()],
        passwordHasher: hasher,
        accountPolicy: const AuthAccountPolicy(
          allowPasswordResetForUnverified: false,
        ),
        passwordResetSender: deliveries.add,
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

    final allowed = await client.postJson('/auth/password-reset/request', {
      'email': user.email,
      '_csrf': csrf.csrf,
    }, headers: headers);
    allowed.assertStatus(HttpStatus.accepted);
    expect(deliveries, hasLength(1));
    final token = deliveries.single.token;

    await store.disable(user.id, reason: 'review');
    final disabledRequest = await client.postJson(
      '/auth/password-reset/request',
      {'email': user.email, '_csrf': csrf.csrf},
      headers: headers,
    );
    disabledRequest.assertStatus(HttpStatus.accepted);
    expect(deliveries, hasLength(1));

    final disabledConfirm = await client.postJson(
      '/auth/password-reset/confirm',
      {'token': token, 'newPassword': 'new-password-456', '_csrf': csrf.csrf},
      headers: headers,
    );
    disabledConfirm.assertStatus(HttpStatus.unauthorized);
    expect(
      disabledConfirm.json()['error'],
      equals('invalid_password_reset_token'),
    );

    await store.enable(user.id);
    final retry = await client.postJson('/auth/password-reset/confirm', {
      'token': token,
      'newPassword': 'new-password-456',
      '_csrf': csrf.csrf,
    }, headers: headers);
    retry.assertStatus(HttpStatus.ok);

    await store.upsert(AuthAccountState(userId: user.id));
    final unverifiedRequest = await client.postJson(
      '/auth/password-reset/request',
      {'email': user.email, '_csrf': csrf.csrf},
      headers: headers,
    );
    unverifiedRequest.assertStatus(HttpStatus.accepted);
    expect(deliveries, hasLength(1));
  });

  test(
    'password reset revokes old JWTs and permits newly issued JWTs',
    () async {
      final store = InMemoryAuthStore();
      final hasher = _testHasher();
      final created = await authorizeCredentialsRegistration(
        store: store,
        passwordHasher: hasher,
        provider: CredentialsProvider(),
        context: Object(),
        credentials: AuthCredentials(
          email: 'jwt-user@example.com',
          password: 'old-password-123',
        ),
      );
      expect(created, isNotNull);
      AuthPasswordResetRequest<EngineContext>? delivered;
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          providers: [CredentialsProvider()],
          sessionStrategy: AuthSessionStrategy.jwt,
          passwordHasher: hasher,
          jwtOptions: const JwtSessionOptions(secret: 'jwt-reset-secret'),
          passwordResetSender: (request) => delivered = request,
        ),
      );
      final engine = _authEngine(manager);
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => client.close());

      final csrf = await _csrf(client);
      final signIn = await client.postJson(
        '/auth/signin/credentials',
        {
          'email': 'jwt-user@example.com',
          'password': 'old-password-123',
          '_csrf': csrf.csrf,
        },
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(csrf.session)],
        },
      );
      signIn.assertStatus(HttpStatus.ok);
      final oldJwt = signIn.cookie('auth_token')!;

      final request = await client.postJson(
        '/auth/password-reset/request',
        {'email': 'jwt-user@example.com', '_csrf': csrf.csrf},
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(csrf.session)],
        },
      );
      request.assertStatus(HttpStatus.accepted);
      expect(delivered, isNotNull);

      final confirmed = await client.postJson(
        '/auth/password-reset/confirm',
        {
          'token': delivered!.token,
          'newPassword': 'new-password-456',
          '_csrf': csrf.csrf,
        },
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(csrf.session)],
        },
      );
      confirmed.assertStatus(HttpStatus.ok);

      final staleSession = await client.get(
        '/auth/session',
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(oldJwt)],
        },
      );
      staleSession.assertStatus(HttpStatus.ok);
      expect(staleSession.body, equals('null'));

      final freshCsrf = await _csrf(client);
      final freshSignIn = await client.postJson(
        '/auth/signin/credentials',
        {
          'email': 'jwt-user@example.com',
          'password': 'new-password-456',
          '_csrf': freshCsrf.csrf,
        },
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(freshCsrf.session)],
        },
      );
      freshSignIn.assertStatus(HttpStatus.ok);
      final freshJwt = freshSignIn.cookie('auth_token')!;
      final freshSession = await client.get(
        '/auth/session',
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(freshJwt)],
        },
      );
      freshSession.assertStatus(HttpStatus.ok);
      expect(freshSession.json()['user']['id'], equals(created!.id));
    },
  );
}

final class _BlockingLimiter implements AuthRateLimiter<EngineContext> {
  AuthRateLimitRequest<EngineContext>? lastRequest;

  @override
  AuthRateLimitDecision check(AuthRateLimitRequest<EngineContext> request) {
    lastRequest = request;
    return const AuthRateLimitDecision.block(retryAfter: Duration(seconds: 11));
  }
}
