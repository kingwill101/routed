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

void main() {
  test(
    'Routed lifecycle issues, reads, and clears the opt-in method cookie',
    () async {
      final store = InMemoryAuthStore();
      final user = await store.users.create(
        AuthUser(id: 'user-1', email: 'user@example.com'),
      );
      final plugin = AuthLastAuthenticationMethodPlugin<EngineContext>(
        signingKey: 'routed-last-authentication-method-signing-key-32-bytes',
        browserStore: const RoutedAuthLastAuthenticationMethodBrowserStore(),
        policy: AuthLastAuthenticationMethodPolicy(
          allowedMethods: {AuthLastAuthenticationMethodId.credentials},
          retention: const Duration(minutes: 5),
        ),
      );
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          providers: <AuthProvider>[
            CredentialsProvider(
              authorize: (_, _, credentials) =>
                  credentials.password == 'correct-password' ? user : null,
            ),
          ],
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          enforceCsrf: false,
          plugins: <AuthServerPlugin<EngineContext>>[plugin],
        ),
      );
      final engine = _authEngine(manager);
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);

      final signIn = await client.postJson(
        '/auth/signin/credentials',
        const <String, dynamic>{
          'email': 'user@example.com',
          'password': 'correct-password',
        },
      );
      signIn.assertStatus(HttpStatus.ok);
      final methodCookie = signIn.cookie('__Host-routed_last_auth_method');
      expect(methodCookie, isNotNull);
      expect(methodCookie!.secure, isTrue);
      expect(methodCookie.httpOnly, isTrue);
      expect(methodCookie.sameSite, SameSite.lax);
      expect(methodCookie.value, isNot(contains('user@example.com')));
      expect(methodCookie.value, isNot(contains('correct-password')));
      final sessionCookie = signIn.cookie('test_session');
      expect(sessionCookie, isNotNull);

      final read = await client.get(
        '/auth/last-authentication-method',
        headers: <String, List<String>>{
          HttpHeaders.cookieHeader: [_cookieHeader(methodCookie)],
        },
      );
      read.assertStatus(HttpStatus.ok);
      expect(read.json()['method'], 'credentials');
      expect(read.body, isNot(contains('correct-password')));

      final replacement = methodCookie.value.endsWith('A') ? 'B' : 'A';
      final tamperedValue =
          '${methodCookie.value.substring(0, methodCookie.value.length - 1)}$replacement';
      final tamperedClient = TestClient(RoutedRequestHandler(engine));
      addTearDown(tamperedClient.close);
      final tampered = await tamperedClient.get(
        '/auth/last-authentication-method',
        headers: <String, List<String>>{
          HttpHeaders.cookieHeader: ['${methodCookie.name}=$tamperedValue'],
        },
      );
      tampered.assertStatus(HttpStatus.ok);
      expect(tampered.body.trim(), 'null');
      expect(tampered.cookie('__Host-routed_last_auth_method')?.maxAge, 0);

      final signedOut = await client.postJson(
        '/auth/signout',
        const <String, dynamic>{},
        headers: <String, List<String>>{
          HttpHeaders.cookieHeader: [
            _cookieHeader(sessionCookie!),
            _cookieHeader(methodCookie),
          ],
        },
      );
      signedOut.assertStatus(HttpStatus.ok);
      final expired = signedOut.cookie('__Host-routed_last_auth_method');
      expect(expired, isNotNull);
      expect(expired!.maxAge, lessThanOrEqualTo(0));
      expect(expired.value, isEmpty);
    },
  );

  test(
    'failed Routed credentials do not create or replace method state',
    () async {
      final store = InMemoryAuthStore();
      final user = await store.users.create(
        AuthUser(id: 'user-1', email: 'user@example.com'),
      );
      final plugin = AuthLastAuthenticationMethodPlugin<EngineContext>(
        signingKey: 'routed-last-authentication-method-signing-key-32-bytes',
        browserStore: const RoutedAuthLastAuthenticationMethodBrowserStore(),
        policy: AuthLastAuthenticationMethodPolicy(
          allowedMethods: {AuthLastAuthenticationMethodId.credentials},
        ),
      );
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          providers: <AuthProvider>[
            CredentialsProvider(
              authorize: (_, _, credentials) =>
                  credentials.password == 'correct-password' ? user : null,
            ),
          ],
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          enforceCsrf: false,
          plugins: <AuthServerPlugin<EngineContext>>[plugin],
        ),
      );
      final engine = _authEngine(manager);
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);

      final failed = await client.postJson(
        '/auth/signin/credentials',
        const <String, dynamic>{
          'email': 'user@example.com',
          'password': 'wrong-password',
        },
      );
      failed.assertStatus(HttpStatus.unauthorized);
      expect(failed.cookie('__Host-routed_last_auth_method'), isNull);
    },
  );

  test('Routed records the method only after JWT issuance succeeds', () async {
    final store = InMemoryAuthStore();
    final user = await store.users.create(
      AuthUser(id: 'jwt-user', email: 'jwt@example.com'),
    );
    final plugin = AuthLastAuthenticationMethodPlugin<EngineContext>(
      signingKey: 'routed-last-authentication-method-signing-key-32-bytes',
      browserStore: const RoutedAuthLastAuthenticationMethodBrowserStore(),
      policy: AuthLastAuthenticationMethodPolicy(
        allowedMethods: {AuthLastAuthenticationMethodId.credentials},
      ),
    );
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        providers: <AuthProvider>[
          CredentialsProvider(
            authorize: (_, _, credentials) =>
                credentials.password == 'correct-password' ? user : null,
          ),
        ],
        store: store,
        storeMode: AuthStoreMode.ephemeral,
        enforceCsrf: false,
        sessionStrategy: AuthSessionStrategy.jwt,
        jwtOptions: const JwtSessionOptions(secret: 'jwt-issuance-test-secret'),
        plugins: <AuthServerPlugin<EngineContext>>[plugin],
      ),
    );
    final engine = _authEngine(manager);
    await engine.initialize();
    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(client.close);

    final signIn = await client.postJson(
      '/auth/signin/credentials',
      const <String, dynamic>{
        'email': 'jwt@example.com',
        'password': 'correct-password',
      },
    );

    signIn.assertStatus(HttpStatus.ok);
    expect(signIn.cookie(manager.options.jwtOptions.cookieName), isNotNull);
    expect(signIn.cookie('__Host-routed_last_auth_method'), isNotNull);
  });

  test('direct account deletion clears the method cookie', () async {
    final store = InMemoryAuthStore();
    final user = AuthUser(id: 'direct-user', email: 'direct@example.com');
    final hasher = Argon2idPasswordHasher(
      iterations: 1,
      memoryKiB: 8,
      derivedKeyLength: 16,
    );
    final now = DateTime.utc(2026, 8, 20);
    await store.credentials.register(
      user,
      AuthPasswordCredential(
        id: 'direct-credential',
        userId: user.id,
        identifier: user.email!,
        passwordHash: hasher.hash('current-password'),
        createdAt: now,
        updatedAt: now,
      ),
    );
    final plugin = AuthLastAuthenticationMethodPlugin<EngineContext>(
      signingKey: 'routed-last-authentication-method-signing-key-32-bytes',
      browserStore: const RoutedAuthLastAuthenticationMethodBrowserStore(),
      policy: AuthLastAuthenticationMethodPolicy(
        allowedMethods: {AuthLastAuthenticationMethodId.credentials},
      ),
    );
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        providers: <AuthProvider>[CredentialsProvider()],
        store: store,
        storeMode: AuthStoreMode.ephemeral,
        passwordHasher: hasher,
        enforceCsrf: false,
        plugins: <AuthServerPlugin<EngineContext>>[plugin],
      ),
    );
    final engine = _authEngine(manager);
    await engine.initialize();
    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(client.close);

    final signIn = await client.postJson(
      '/auth/signin/credentials',
      const <String, dynamic>{
        'email': 'direct@example.com',
        'password': 'current-password',
      },
    );
    signIn.assertStatus(HttpStatus.ok);
    final sessionCookie = signIn.cookie('test_session')!;
    final methodCookie = signIn.cookie('__Host-routed_last_auth_method')!;

    final deletion = await client.postJson(
      '/auth/account/delete',
      const <String, dynamic>{'currentPassword': 'current-password'},
      headers: <String, List<String>>{
        HttpHeaders.cookieHeader: [
          _cookieHeader(sessionCookie),
          _cookieHeader(methodCookie),
        ],
      },
    );

    deletion.assertStatus(HttpStatus.ok);
    expect(deletion.cookie('__Host-routed_last_auth_method')?.maxAge, 0);
  });

  test('confirmed account deletion clears the method cookie', () async {
    final store = InMemoryAuthStore();
    final user = AuthUser(id: 'confirmed-user', email: 'confirm@example.com');
    final hasher = Argon2idPasswordHasher(
      iterations: 1,
      memoryKiB: 8,
      derivedKeyLength: 16,
    );
    final now = DateTime.utc(2026, 8, 20);
    await store.credentials.register(
      user,
      AuthPasswordCredential(
        id: 'confirmed-credential',
        userId: user.id,
        identifier: user.email!,
        passwordHash: hasher.hash('current-password'),
        createdAt: now,
        updatedAt: now,
      ),
    );
    AuthAccountDeletionDelivery<EngineContext>? delivery;
    final plugin = AuthLastAuthenticationMethodPlugin<EngineContext>(
      signingKey: 'routed-last-authentication-method-signing-key-32-bytes',
      browserStore: const RoutedAuthLastAuthenticationMethodBrowserStore(),
      policy: AuthLastAuthenticationMethodPolicy(
        allowedMethods: {AuthLastAuthenticationMethodId.credentials},
      ),
    );
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        providers: <AuthProvider>[CredentialsProvider()],
        store: store,
        storeMode: AuthStoreMode.ephemeral,
        passwordHasher: hasher,
        accountDeletionSender: (sent) => delivery = sent,
        enforceCsrf: false,
        plugins: <AuthServerPlugin<EngineContext>>[plugin],
      ),
    );
    final engine = _authEngine(manager);
    await engine.initialize();
    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(client.close);

    final signIn = await client.postJson(
      '/auth/signin/credentials',
      const <String, dynamic>{
        'email': 'confirm@example.com',
        'password': 'current-password',
      },
    );
    signIn.assertStatus(HttpStatus.ok);
    final sessionCookie = signIn.cookie('test_session')!;
    final methodCookie = signIn.cookie('__Host-routed_last_auth_method')!;
    final headers = <String, List<String>>{
      HttpHeaders.cookieHeader: [
        _cookieHeader(sessionCookie),
        _cookieHeader(methodCookie),
      ],
    };

    final request = await client.postJson(
      '/auth/account/delete/request',
      const <String, dynamic>{'currentPassword': 'current-password'},
      headers: headers,
    );
    request.assertStatus(HttpStatus.accepted);
    expect(delivery, isNotNull);

    final confirmation = await client.postJson(
      '/auth/account/delete/confirm',
      <String, dynamic>{'token': delivery!.token},
      headers: headers,
    );

    confirmation.assertStatus(HttpStatus.ok);
    expect(confirmation.cookie('__Host-routed_last_auth_method')?.maxAge, 0);
  });
}
