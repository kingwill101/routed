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

Future<({String csrf, Cookie session})> _login(TestClient client) async {
  final csrfResponse = await client.get('/auth/csrf');
  final csrf = csrfResponse.json()['csrfToken'] as String;
  final session = csrfResponse.cookie('test_session')!;
  final login = await client.postJson(
    '/auth/signin/credentials',
    {
      'email': 'user@example.com',
      'password': 'old-password-123',
      '_csrf': csrf,
    },
    headers: {
      HttpHeaders.cookieHeader: [_cookieHeader(session)],
    },
  );
  login.assertStatus(HttpStatus.ok);
  return (csrf: csrf, session: login.cookie('test_session')!);
}

void main() {
  test('lists sessions and revokes other sessions', () async {
    final store = InMemoryAuthStore();
    final hasher = Argon2idPasswordHasher(
      iterations: 1,
      memoryKiB: 8,
      derivedKeyLength: 16,
    );
    await authorizeCredentialsRegistration(
      store: store,
      passwordHasher: hasher,
      provider: CredentialsProvider(),
      context: Object(),
      credentials: AuthCredentials(
        email: 'user@example.com',
        password: 'old-password-123',
      ),
    );
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: store,
        storeMode: AuthStoreMode.ephemeral,
        providers: [CredentialsProvider()],
        passwordHasher: hasher,
      ),
    );
    final engine = _authEngine(manager);
    await engine.initialize();
    final client = TestClient(RoutedRequestHandler(engine));
    final secondClient = TestClient(RoutedRequestHandler(engine));
    addTearDown(() async {
      await client.close();
      await secondClient.close();
    });

    final first = await _login(client);
    await _login(secondClient);

    final sessions = await client.get(
      '/auth/sessions',
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(first.session)],
      },
    );
    sessions.assertStatus(HttpStatus.ok);
    expect(sessions.json()['sessions'], hasLength(2));
    expect(
      (sessions.json()['sessions'] as List).where(
        (session) => session['isCurrent'] == true,
      ),
      hasLength(1),
    );

    final revokeOthers = await client.postJson(
      '/auth/sessions/revoke-others',
      {'_csrf': first.csrf},
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(first.session)],
      },
    );
    revokeOthers.assertStatus(HttpStatus.ok);
    expect(revokeOthers.json()['revoked'], 1);

    final remaining = await client.get(
      '/auth/sessions',
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(first.session)],
      },
    );
    remaining.assertStatus(HttpStatus.ok);
    expect(remaining.json()['sessions'], hasLength(1));
  });

  test(
    'session-management routes are not registered for JWT sessions',
    () async {
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [CredentialsProvider()],
          sessionStrategy: AuthSessionStrategy.jwt,
        ),
      );
      final engine = _authEngine(manager);
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => client.close());

      final response = await client.get('/auth/sessions');

      response.assertStatus(HttpStatus.notFound);
    },
  );
}
