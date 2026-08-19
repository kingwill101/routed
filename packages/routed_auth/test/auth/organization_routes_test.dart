import 'dart:async';
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
  test(
    'feature routes delegate collisions and exclude server-only entries',
    () {
      AuthManager manager(bool serverOnly) => AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: const [],
          plugins: [_CollisionPlugin(serverOnly: serverOnly)],
        ),
      );

      final collidingEngine = _engineWithoutRoutes();
      expect(
        () =>
            AuthRoutes(manager(false)).register(collidingEngine.defaultRouter),
        returnsNormally,
      );
      final warnings = <String>[];
      final routes = runZoned(
        collidingEngine.getAllRoutes,
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => warnings.add(line),
        ),
      );
      expect(
        routes.where(
          (route) => route.method == 'GET' && route.path == '/auth/providers',
        ),
        hasLength(1),
      );
      expect(
        warnings.join('\n'),
        contains('Duplicate route registered for [GET] /auth/providers'),
      );

      final serverOnlyEngine = _engineWithoutRoutes();
      expect(
        () =>
            AuthRoutes(manager(true)).register(serverOnlyEngine.defaultRouter),
        returnsNormally,
      );
    },
  );

  test(
    'organization routes are absent until the feature is composed',
    () async {
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

      final response = await client.get(
        '/auth/organization/check-slug?slug=acme',
      );
      response.assertStatus(HttpStatus.notFound);
    },
  );

  test(
    'contributed routes share session, CSRF, active state, and limiter',
    () async {
      final limiter = _RecordingLimiter();
      final organization = OrganizationPlugin<EngineContext>(
        store: InMemoryAuthOrganizationStore(),
      );
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            CredentialsProvider(
              authorize: (_, _, credentials) => AuthUser(
                id: 'user-1',
                email: credentials.email,
                attributes: const {'emailVerified': true},
              ),
            ),
          ],
          plugins: [organization],
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
        {'email': 'user@example.com', 'password': 'secret', '_csrf': csrf},
        headers: {
          HttpHeaders.cookieHeader: [_cookie(initialCookie)],
        },
      );
      login.assertStatus(HttpStatus.ok);
      final cookie = login.cookie('test_session')!;

      final rejected = await client.postJson(
        '/auth/organization/create',
        {'name': 'Acme', 'slug': 'acme', '_csrf': 'wrong'},
        headers: {
          HttpHeaders.cookieHeader: [_cookie(cookie)],
        },
      );
      rejected.assertStatus(HttpStatus.forbidden);
      expect(rejected.json()['error'], 'invalid_csrf');

      limiter.operations.clear();
      final created = await client.postJson(
        '/auth/organization/create',
        {'name': 'Acme', 'slug': 'acme', '_csrf': csrf},
        headers: {
          HttpHeaders.cookieHeader: [_cookie(cookie)],
        },
      );
      created.assertStatus(HttpStatus.ok);
      final organizationId = created.json()['data']['id'] as String;
      expect(
        limiter.operations,
        contains(const AuthRateLimitOperation('organization', 'create')),
      );

      final active = await client.postJson(
        '/auth/organization/set-active',
        {'organizationId': organizationId, '_csrf': csrf},
        headers: {
          HttpHeaders.cookieHeader: [_cookie(cookie)],
        },
      );
      active.assertStatus(HttpStatus.ok);
      final activeCookie = active.cookie('test_session') ?? cookie;

      final current = await client.get(
        '/auth/organization/get',
        headers: {
          HttpHeaders.cookieHeader: [_cookie(activeCookie)],
        },
      );
      current.assertStatus(HttpStatus.ok);
      expect(current.json()['id'], organizationId);

      final permission = await client.get(
        '/auth/organization/has-permission?organizationId=$organizationId&resource=organization&action=delete',
        headers: {
          HttpHeaders.cookieHeader: [_cookie(activeCookie)],
        },
      );
      permission.assertStatus(HttpStatus.ok);
      expect(permission.json()['allowed'], isTrue);
    },
  );
}

Engine _engineWithoutRoutes() => testEngine(
  config: EngineConfig(
    security: const EngineSecurityFeatures(csrfProtection: false),
  ),
  providers: [RoutedSessionsProvider(_sessionConfig())],
);

final class _RecordingLimiter implements AuthRateLimiter<EngineContext> {
  final List<AuthRateLimitOperation> operations = [];

  @override
  AuthRateLimitDecision check(AuthRateLimitRequest<EngineContext> request) {
    operations.add(request.operation);
    return const AuthRateLimitDecision.allow();
  }
}

final class _CollisionPlugin
    implements
        AuthServerPlugin<EngineContext>,
        AuthEndpointContributor<EngineContext> {
  const _CollisionPlugin({required this.serverOnly});

  final bool serverOnly;

  @override
  String get id => serverOnly ? 'server-only' : 'collision';

  @override
  Iterable<AuthEndpointDescriptor<EngineContext>> get endpoints => [
    _CollisionEndpoint(serverOnly: serverOnly),
  ];

  @override
  void configure(AuthServerPluginContext<EngineContext> context) {}
}

final class _CollisionEndpoint
    implements AuthEndpointDescriptor<EngineContext> {
  const _CollisionEndpoint({required this.serverOnly});

  @override
  final bool serverOnly;
  @override
  String get id => 'feature.providers';
  @override
  AuthOperationMethod get method => AuthOperationMethod.get;
  @override
  String get path => '/providers';
  @override
  AuthOperationAuthentication get authentication =>
      AuthOperationAuthentication.none;
  @override
  AuthOperationOriginPolicy get originPolicy => AuthOperationOriginPolicy.none;
  @override
  AuthOperationCsrfPolicy get csrfPolicy => AuthOperationCsrfPolicy.none;
  @override
  AuthRateLimitOperation? get rateLimitOperation => null;

  @override
  Object? invoke(
    AuthOperationInvocation<EngineContext> invocation,
    Map<String, dynamic> input,
  ) => const {'ok': true};
}
