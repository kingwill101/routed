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

Engine _engine(AuthManager manager) {
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

String _cookie(Cookie cookie) => '${cookie.name}=${cookie.value}';

void main() {
  test('admin routes are absent until the feature is composed', () async {
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        providers: const [],
      ),
    );
    final engine = _engine(manager);
    await engine.initialize();
    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(client.close);
    (await client.get(
      '/auth/admin/list-users',
    )).assertStatus(HttpStatus.notFound);
  });

  test(
    'admin routes share authentication, CSRF, and namespaced rate limits',
    () async {
      final core = InMemoryAuthStore();
      final admin = AuthUser(
        id: 'admin-1',
        email: 'admin@example.com',
        roles: const ['admin'],
      );
      await core.users.create(admin);
      final limiter = _RecordingLimiter();
      final feature = AdminPlugin<EngineContext>(
        store: InMemoryAuthAdminStore(core),
      );
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: core,
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            CredentialsProvider(
              authorize: (_, _, credentials) async =>
                  core.users.findByEmail(credentials.email!),
            ),
          ],
          plugins: [feature],
          rateLimiter: limiter,
        ),
      );
      final engine = _engine(manager);
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);

      final csrfResponse = await client.get('/auth/csrf');
      final csrf = csrfResponse.json()['csrfToken'] as String;
      final initialCookie = csrfResponse.cookie('test_session')!;
      final login = await client.postJson(
        '/auth/signin/credentials',
        {'email': admin.email, 'password': 'ignored-password', '_csrf': csrf},
        headers: {
          HttpHeaders.cookieHeader: [_cookie(initialCookie)],
        },
      );
      login.assertStatus(HttpStatus.ok);
      final cookie = login.cookie('test_session')!;

      final rejected = await client.postJson(
        '/auth/admin/create-user',
        {
          'email': 'user@example.com',
          'name': 'User',
          'password': 'long-enough-password',
          '_csrf': 'wrong',
        },
        headers: {
          HttpHeaders.cookieHeader: [_cookie(cookie)],
        },
      );
      rejected.assertStatus(HttpStatus.forbidden);

      limiter.operations.clear();
      final created = await client.postJson(
        '/auth/admin/create-user',
        {
          'email': 'user@example.com',
          'name': 'User',
          'password': 'long-enough-password',
          '_csrf': csrf,
        },
        headers: {
          HttpHeaders.cookieHeader: [_cookie(cookie)],
        },
      );
      created.assertStatus(HttpStatus.ok);
      expect(created.json()['data']['email'], 'user@example.com');
      expect(
        limiter.operations,
        contains(const AuthRateLimitOperation('admin', 'createUser')),
      );

      final listed = await client.get(
        '/auth/admin/list-users?search=user&limit=10',
        headers: {
          HttpHeaders.cookieHeader: [_cookie(cookie)],
        },
      );
      listed.assertStatus(HttpStatus.ok);
      expect(listed.json()['total'], 1);

      final userId = created.json()['data']['id'] as String;
      final impersonated = await client.postJson(
        '/auth/admin/impersonate-user',
        {'userId': userId, '_csrf': csrf},
        headers: {
          HttpHeaders.cookieHeader: [_cookie(cookie)],
        },
      );
      impersonated.assertStatus(HttpStatus.ok);
      expect(impersonated.json()['data']['user']['id'], userId);
      final impersonatedCookie = impersonated.cookie('test_session')!;

      final active = await client.get(
        '/auth/session',
        headers: {
          HttpHeaders.cookieHeader: [_cookie(impersonatedCookie)],
        },
      );
      active.assertStatus(HttpStatus.ok);
      expect(active.json()['user']['id'], userId);

      final stopped = await client.postJson(
        '/auth/admin/stop-impersonating',
        {'_csrf': csrf},
        headers: {
          HttpHeaders.cookieHeader: [_cookie(impersonatedCookie)],
        },
      );
      stopped.assertStatus(HttpStatus.ok);
      expect(stopped.json()['data']['session']['user']['id'], admin.id);
      final restoredAdminCookie = stopped.cookie('test_session')!;

      final targetClient = TestClient(RoutedRequestHandler(engine));
      addTearDown(targetClient.close);
      final targetCsrfResponse = await targetClient.get('/auth/csrf');
      final targetCsrf = targetCsrfResponse.json()['csrfToken'] as String;
      final targetLogin = await targetClient.postJson(
        '/auth/signin/credentials',
        {
          'email': 'user@example.com',
          'password': 'ignored-password',
          '_csrf': targetCsrf,
        },
        headers: {
          HttpHeaders.cookieHeader: [
            _cookie(targetCsrfResponse.cookie('test_session')!),
          ],
        },
      );
      targetLogin.assertStatus(HttpStatus.ok);
      final targetCookie = targetLogin.cookie('test_session')!;

      final banned = await client.postJson(
        '/auth/admin/ban-user',
        {'userId': userId, '_csrf': csrf},
        headers: {
          HttpHeaders.cookieHeader: [_cookie(restoredAdminCookie)],
        },
      );
      banned.assertStatus(HttpStatus.ok);
      final rejectedSession = await targetClient.get(
        '/auth/session',
        headers: {
          HttpHeaders.cookieHeader: [_cookie(targetCookie)],
        },
      );
      rejectedSession.assertStatus(HttpStatus.ok);
      expect(rejectedSession.body, 'null');

      final bannedCsrfResponse = await targetClient.get('/auth/csrf');
      final bannedCsrf = bannedCsrfResponse.json()['csrfToken'] as String;
      final bannedLogin = await targetClient.postJson(
        '/auth/signin/credentials',
        {
          'email': 'user@example.com',
          'password': 'ignored-password',
          '_csrf': bannedCsrf,
        },
        headers: {
          HttpHeaders.cookieHeader: [
            _cookie(bannedCsrfResponse.cookie('test_session')!),
          ],
        },
      );
      bannedLogin.assertStatus(HttpStatus.unauthorized);
      expect(bannedLogin.json().toString(), isNot(contains('abuse')));
    },
  );
}

final class _RecordingLimiter implements AuthRateLimiter<EngineContext> {
  final List<AuthRateLimitOperation> operations = [];

  @override
  AuthRateLimitDecision check(AuthRateLimitRequest<EngineContext> request) {
    operations.add(request.operation);
    return const AuthRateLimitDecision.allow();
  }
}
