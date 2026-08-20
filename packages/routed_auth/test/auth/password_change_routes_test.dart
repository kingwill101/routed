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
      path: '/',
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

Argon2idPasswordHasher _testHasher() =>
    Argon2idPasswordHasher(iterations: 1, memoryKiB: 8, derivedKeyLength: 16);

void main() {
  test(
    'password change reauthenticates and expires the current session',
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
      final trustedDeviceStore = InMemoryAuthTwoFactorTrustedDeviceStore();
      final changeNow = DateTime.now().toUtc();
      trustedDeviceStore.create(
        AuthTwoFactorTrustedDeviceRecord(
          id: 'trusted-change-1',
          userId: created!.id,
          tokenHash: hashOpaqueToken('old-change-device'),
          createdAt: changeNow,
          expiresAt: changeNow.add(const Duration(days: 30)),
        ),
      );
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
        ),
      );
      final engine = _authEngine(manager);
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => client.close());

      final csrfResponse = await client.get('/auth/csrf');
      final csrf = csrfResponse.json()['csrfToken'] as String;
      final initialCookie = csrfResponse.cookie('test_session')!;
      final login = await client.postJson(
        '/auth/signin/credentials',
        {
          'email': 'user@example.com',
          'password': 'old-password-123',
          '_csrf': csrf,
        },
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(initialCookie)],
        },
      );
      login.assertStatus(HttpStatus.ok);
      final authCookie = login.cookie('test_session')!;

      final changed = await client.postJson(
        '/auth/password/change',
        {
          'identifier': 'USER@example.com',
          'currentPassword': 'old-password-123',
          'newPassword': 'new-password-456',
          '_csrf': csrf,
        },
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(authCookie)],
        },
      );
      changed.assertStatus(HttpStatus.ok);
      expect(changed.json()['status'], 'password_changed');
      expect(changed.cookie('test_session')?.value, isEmpty);
      expect(
        trustedDeviceStore.findActive(
          created.id,
          hashOpaqueToken('old-change-device'),
          now: DateTime.now().toUtc(),
        ),
        isNull,
      );

      final freshCsrfResponse = await client.get('/auth/csrf');
      final freshCsrf = freshCsrfResponse.json()['csrfToken'] as String;
      final freshCookie = freshCsrfResponse.cookie('test_session')!;
      final oldPassword = await client.postJson(
        '/auth/signin/credentials',
        {
          'email': 'user@example.com',
          'password': 'old-password-123',
          '_csrf': freshCsrf,
        },
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(freshCookie)],
        },
      );
      oldPassword.assertStatus(HttpStatus.unauthorized);

      final newPassword = await client.postJson(
        '/auth/signin/credentials',
        {
          'email': 'user@example.com',
          'password': 'new-password-456',
          '_csrf': freshCsrf,
        },
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(freshCookie)],
        },
      );
      newPassword.assertStatus(HttpStatus.ok);
    },
  );

  test('JWT password change rotates the token version', () async {
    final store = InMemoryAuthStore();
    final hasher = _testHasher();
    final user = await authorizeCredentialsRegistration(
      store: store,
      passwordHasher: hasher,
      provider: CredentialsProvider(),
      context: Object(),
      credentials: AuthCredentials(
        email: 'jwt-user@example.com',
        password: 'old-password-123',
      ),
    );
    expect(user, isNotNull);
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: store,
        storeMode: AuthStoreMode.ephemeral,
        providers: [CredentialsProvider()],
        sessionStrategy: AuthSessionStrategy.jwt,
        passwordHasher: hasher,
        jwtOptions: const JwtSessionOptions(secret: 'jwt-change-secret'),
      ),
    );
    final engine = _authEngine(manager);
    await engine.initialize();
    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(() async => client.close());

    final csrfResponse = await client.get('/auth/csrf');
    final csrf = csrfResponse.json()['csrfToken'] as String;
    final sessionCookie = csrfResponse.cookie('test_session')!;
    final signIn = await client.postJson(
      '/auth/signin/credentials',
      {
        'email': 'jwt-user@example.com',
        'password': 'old-password-123',
        '_csrf': csrf,
      },
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
      },
    );
    signIn.assertStatus(HttpStatus.ok);
    final oldJwt = signIn.cookie('auth_token')!;

    final response = await client.postJson(
      '/auth/password/change',
      {
        'identifier': 'jwt-user@example.com',
        'currentPassword': 'old-password-123',
        'newPassword': 'new-password-456',
        '_csrf': csrf,
      },
      headers: {
        HttpHeaders.cookieHeader: [
          _cookieHeader(sessionCookie),
          _cookieHeader(oldJwt),
        ],
      },
    );

    response.assertStatus(HttpStatus.ok);
    expect(response.json()['status'], equals('password_changed'));
    expect(response.cookie('auth_token')?.value, isEmpty);

    final staleSession = await client.get(
      '/auth/session',
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(oldJwt)],
      },
    );
    staleSession.assertStatus(HttpStatus.ok);
    expect(staleSession.body, equals('null'));

    final freshSignIn = await client.postJson(
      '/auth/signin/credentials',
      {
        'email': 'jwt-user@example.com',
        'password': 'new-password-456',
        '_csrf': csrf,
      },
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
      },
    );
    freshSignIn.assertStatus(HttpStatus.ok);
    expect(freshSignIn.cookie('auth_token'), isNotNull);
    expect(user, isNotNull);
  });
}
