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

String _cookieHeader(Cookie cookie) => '${cookie.name}=${cookie.value}';

void main() {
  test(
    'anonymous sign-in rejects cross-origin forms but allows same-origin and native clients',
    () async {
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: const [],
          plugins: [AnonymousPlugin<EngineContext>()],
        ),
      );
      final engine = testEngine(
        config: EngineConfig(
          security: const EngineSecurityFeatures(csrfProtection: false),
        ),
        providers: [RoutedSessionsProvider(_sessionConfig())],
      );
      engine.addGlobalMiddleware(sessionMiddleware());
      engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());
      AuthRoutes(manager).register(engine.defaultRouter);
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);

      final crossOrigin = await client.post(
        '/auth/sign-in/anonymous',
        '',
        headers: const <String, List<String>>{
          HttpHeaders.contentTypeHeader: ['application/x-www-form-urlencoded'],
          'Origin': ['https://attacker.example'],
          'Sec-Fetch-Site': ['cross-site'],
        },
      );
      crossOrigin.assertStatus(HttpStatus.forbidden);
      expect(crossOrigin.json(), <String, dynamic>{'error': 'invalid_origin'});

      final sameOrigin = await client.post(
        '/auth/sign-in/anonymous',
        '',
        headers: const <String, List<String>>{
          HttpHeaders.contentTypeHeader: ['application/x-www-form-urlencoded'],
          'Origin': ['http://server_testing.internal'],
          'Sec-Fetch-Site': ['same-origin'],
        },
      );
      sameOrigin.assertStatus(HttpStatus.ok);
      expect(sameOrigin.json()['user']['isAnonymous'], isTrue);

      final native = await client.postJson(
        '/auth/sign-in/anonymous',
        const <String, dynamic>{},
      );
      native.assertStatus(HttpStatus.ok);
      expect(native.json()['user']['isAnonymous'], isTrue);
    },
  );

  test('Routed supports anonymous sessions and account deletion', () async {
    final feature = AnonymousPlugin<EngineContext>();
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        providers: const [],
        plugins: [feature],
      ),
    );
    final sessionConfig = _sessionConfig();
    final engine = testEngine(
      config: EngineConfig(
        security: const EngineSecurityFeatures(csrfProtection: false),
      ),
      providers: [RoutedSessionsProvider(sessionConfig)],
    );
    engine.addGlobalMiddleware(sessionMiddleware());
    engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());
    AuthRoutes(manager).register(engine.defaultRouter);
    await engine.initialize();
    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(client.close);

    final signedIn = await client.postJson(
      '/auth/sign-in/anonymous',
      <String, dynamic>{},
    );
    signedIn.assertStatus(HttpStatus.ok);
    expect(signedIn.json()['user']['isAnonymous'], isTrue);
    final sessionCookie = signedIn.cookie('test_session');
    expect(sessionCookie, isNotNull);
    final anonymousId = signedIn.json()['user']['id'] as String;
    expect(await manager.store.users.findById(anonymousId), isNotNull);

    final csrf = await client.get(
      '/auth/csrf',
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
      },
    );
    csrf.assertStatus(HttpStatus.ok);
    final crossOrigin = await client.postJson(
      '/auth/delete-anonymous-user',
      {'_csrf': csrf.json()['csrfToken']},
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
        'Origin': ['https://attacker.example'],
        'Sec-Fetch-Site': ['cross-site'],
      },
    );
    crossOrigin.assertStatus(HttpStatus.forbidden);
    expect(crossOrigin.json(), {'error': 'invalid_origin'});
    expect(await manager.store.users.findById(anonymousId), isNotNull);

    final missingCsrf = await client.postJson(
      '/auth/delete-anonymous-user',
      const <String, dynamic>{},
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
        'Origin': ['http://server_testing.internal'],
        'Sec-Fetch-Site': ['same-origin'],
      },
    );
    missingCsrf.assertStatus(HttpStatus.forbidden);
    expect(missingCsrf.json(), {'error': 'invalid_csrf'});
    expect(await manager.store.users.findById(anonymousId), isNotNull);

    final deleted = await client.postJson(
      '/auth/delete-anonymous-user',
      {'_csrf': csrf.json()['csrfToken']},
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
        'Origin': ['http://server_testing.internal'],
        'Sec-Fetch-Site': ['same-origin'],
      },
    );
    deleted.assertStatus(HttpStatus.ok);
    expect(deleted.json()['status'], 'anonymous_deleted');
    expect(await manager.store.users.findById(anonymousId), isNull);
  });

  test(
    'JWT account upgrade keeps anonymous data when sign-in is denied',
    () async {
      final store = InMemoryAuthStore();
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            CredentialsProvider(
              authorize: (_, _, credentials) =>
                  AuthUser(id: 'target-user', email: credentials.email),
            ),
          ],
          plugins: [AnonymousPlugin<EngineContext>()],
          sessionStrategy: AuthSessionStrategy.jwt,
          jwtOptions: const JwtSessionOptions(secret: 'anonymous-jwt-secret'),
          callbacks: AuthCallbacks<EngineContext>(
            signIn: (context) => context.user.isAnonymous
                ? const AuthSignInResult.allow()
                : const AuthSignInResult.deny(),
          ),
        ),
      );
      final engine = testEngine(
        config: EngineConfig(
          security: const EngineSecurityFeatures(csrfProtection: false),
        ),
        providers: [RoutedSessionsProvider(_sessionConfig())],
      );
      engine.addGlobalMiddleware(sessionMiddleware());
      engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());
      AuthRoutes(manager).register(engine.defaultRouter);
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);

      final csrf = await client.get('/auth/csrf');
      final sessionCookie = csrf.cookie('test_session')!;
      final anonymous = await client.postJson(
        '/auth/sign-in/anonymous',
        const <String, dynamic>{},
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
        },
      );
      expect(anonymous.statusCode, HttpStatus.ok, reason: anonymous.body);
      final anonymousId = anonymous.json()['user']['id'] as String;
      final anonymousJwt = anonymous.cookie('auth_token')!;

      final denied = await client.postJson(
        '/auth/signin/credentials',
        <String, dynamic>{
          'email': 'target@example.com',
          'password': 'password',
          '_csrf': csrf.json()['csrfToken'],
        },
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
          HttpHeaders.authorizationHeader: ['Bearer ${anonymousJwt.value}'],
        },
      );

      denied.assertStatus(HttpStatus.unauthorized);
      expect(denied.json()['error'], 'sign_in_blocked');
      expect(await store.users.findById(anonymousId), isNotNull);
    },
  );

  test(
    'JWT account upgrade finalizes after replacement session issuance',
    () async {
      final store = InMemoryAuthStore();
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            CredentialsProvider(
              authorize: (_, _, credentials) =>
                  AuthUser(id: 'target-user', email: credentials.email),
            ),
          ],
          plugins: [AnonymousPlugin<EngineContext>()],
          sessionStrategy: AuthSessionStrategy.jwt,
          jwtOptions: const JwtSessionOptions(secret: 'anonymous-jwt-secret'),
        ),
      );
      final engine = testEngine(
        config: EngineConfig(
          security: const EngineSecurityFeatures(csrfProtection: false),
        ),
        providers: [RoutedSessionsProvider(_sessionConfig())],
      );
      engine.addGlobalMiddleware(sessionMiddleware());
      engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());
      AuthRoutes(manager).register(engine.defaultRouter);
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);

      final csrf = await client.get('/auth/csrf');
      final sessionCookie = csrf.cookie('test_session')!;
      final anonymous = await client.postJson(
        '/auth/sign-in/anonymous',
        const <String, dynamic>{},
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
        },
      );
      expect(anonymous.statusCode, HttpStatus.ok, reason: anonymous.body);
      final anonymousId = anonymous.json()['user']['id'] as String;
      final anonymousJwt = anonymous.cookie('auth_token')!;

      final upgraded = await client.postJson(
        '/auth/signin/credentials',
        <String, dynamic>{
          'email': 'target@example.com',
          'password': 'password',
          '_csrf': csrf.json()['csrfToken'],
        },
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
          HttpHeaders.authorizationHeader: ['Bearer ${anonymousJwt.value}'],
        },
      );

      upgraded.assertStatus(HttpStatus.ok);
      expect(await store.users.findById(anonymousId), isNull);
      expect(upgraded.cookie('auth_token'), isNotNull);
    },
  );
}
