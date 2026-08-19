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

String _cookieHeader(Cookie cookie) => '${cookie.name}=${cookie.value}';

void main() {
  test(
    'device authorization is available through Routed HTTP routes',
    () async {
      final store = InMemoryAuthStore();
      final user = await store.users.create(
        AuthUser(id: 'user-1', email: 'user@example.com'),
      );
      final hasher = Argon2idPasswordHasher(
        iterations: 1,
        memoryKiB: 8,
        derivedKeyLength: 16,
      );
      await store.upsertCredentialForAdministration(
        AuthPasswordCredential(
          id: 'credential-1',
          userId: user.id,
          identifier: user.email!,
          passwordHash: hasher.hash('password'),
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      final feature = DeviceAuthorizationFeature<EngineContext>(
        verificationUri: 'https://example.test/device',
        pollInterval: const Duration(milliseconds: 1),
        validateClient: (context, clientId, scopes) => clientId == 'cli-1',
        issueToken:
            ({
              required context,
              required user,
              required clientId,
              required scopes,
              required authorizationId,
            }) => AuthDeviceAccessToken(
              accessToken: 'access-$authorizationId',
              expiresIn: const Duration(minutes: 5),
              scopes: scopes,
            ),
      );
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          passwordHasher: hasher,
          providers: [
            CredentialsProvider(
              authorize: (_, _, credentials) =>
                  credentials.password == 'password' ? user : null,
            ),
          ],
          features: [feature],
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

      final authorization = await client.postJson(
        '/auth/oauth/device/authorize',
        {'client_id': 'cli-1', 'scope': 'openid profile'},
      );
      authorization.assertStatus(HttpStatus.ok);
      final deviceCode = authorization.json()['device_code'] as String;
      final userCode = authorization.json()['user_code'] as String;

      final csrf = await client.get('/auth/csrf');
      csrf.assertStatus(HttpStatus.ok);
      final csrfToken = csrf.json()['csrfToken'] as String;
      final initialCookie = csrf.cookie('test_session');
      expect(initialCookie, isNotNull);
      final signedIn = await client.postJson(
        '/auth/signin/credentials',
        {'email': user.email, 'password': 'password', '_csrf': csrfToken},
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(initialCookie!)],
        },
      );
      signedIn.assertStatus(HttpStatus.ok);
      final sessionCookie = signedIn.cookie('test_session') ?? initialCookie;

      final pending = await client.postJson('/auth/oauth/token', {
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        'client_id': 'cli-1',
        'device_code': deviceCode,
      });
      pending.assertStatus(HttpStatus.badRequest);
      expect(pending.json()['error'], 'authorization_pending');

      final approved = await client.postJson(
        '/auth/oauth/device/approve',
        {'user_code': userCode, '_csrf': csrfToken},
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
        },
      );
      approved.assertStatus(HttpStatus.ok);
      expect(approved.json()['status'], 'approved');

      final token = await client.postJson('/auth/oauth/token', {
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        'client_id': 'cli-1',
        'device_code': deviceCode,
      });
      token.assertStatus(HttpStatus.ok);
      expect(token.json()['access_token'], startsWith('access-'));
      expect(token.json()['scope'], 'openid profile');

      final replay = await client.postJson('/auth/oauth/token', {
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        'client_id': 'cli-1',
        'device_code': deviceCode,
      });
      replay.assertStatus(HttpStatus.badRequest);
      expect(replay.json()['error'], 'invalid_grant');
    },
  );

  test(
    'device approval route rejects missing browser authentication',
    () async {
      final feature = DeviceAuthorizationFeature<EngineContext>(
        verificationUri: 'https://example.test/device',
        validateClient: (context, clientId, scopes) => true,
        issueToken:
            ({
              required context,
              required user,
              required clientId,
              required scopes,
              required authorizationId,
            }) => AuthDeviceAccessToken(
              accessToken: 'unused',
              expiresIn: const Duration(minutes: 5),
            ),
      );
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: const [],
          features: [feature],
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

      final response = await client.postJson('/auth/oauth/device/approve', {
        'user_code': 'ABCD-2345',
      });
      response.assertStatus(HttpStatus.forbidden);
      expect(response.json()['error'], 'invalid_csrf');
    },
  );
}
