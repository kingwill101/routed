import 'dart:convert';
import 'dart:io';

import 'package:routed_auth/routed_auth.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

import '../test_engine.dart';

void main() {
  test(
    'Routed mounts session-authorized managed SCIM connection operations',
    () async {
      final store = InMemoryAuthScimConnectionStore();
      var connectionSequence = 0;
      var credentialSequence = 0;
      var secretSequence = 0;
      final plugin = AuthScimConnectionPlugin<EngineContext>(
        store: store,
        authorize: (request) {
          if (request.invocation.user?.id != 'user-1' ||
              request.organizationId != 'organization-a') {
            return null;
          }
          return AuthScimConnectionManagementPrincipal(
            tenantId: 'tenant-a',
            organizationId: request.organizationId,
            subjectId: request.invocation.user!.id,
          );
        },
        connectionIdGenerator: ({length = 0}) =>
            'connection-${++connectionSequence}-abcdefgh',
        credentialIdGenerator: ({length = 0}) =>
            'credential-${++credentialSequence}-abcdefgh',
        secretGenerator: ({length = 0}) =>
            'secret-${++secretSequence}-abcdefghijklmnopqrstuvwxyz',
        clock: () => DateTime.utc(2030),
      );
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: <AuthProvider>[
            CredentialsProvider(
              authorize: (_, _, credentials) => AuthUser(
                id: 'user-1',
                email: credentials.email,
                attributes: const <String, Object?>{'emailVerified': true},
              ),
            ),
          ],
          plugins: <AuthServerPlugin<EngineContext>>[plugin],
        ),
      );
      final engine = _engine(manager);
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);

      final unauthenticated = await client.get(
        '/auth/scim/connections?organizationId=organization-a',
      );
      unauthenticated.assertStatus(HttpStatus.unauthorized);

      final csrfResponse = await client.get('/auth/csrf');
      final csrf = csrfResponse.json()['csrfToken'] as String;
      final initialCookie = csrfResponse.cookie('test_session')!;
      final login = await client.postJson(
        '/auth/signin/credentials',
        <String, Object?>{
          'email': 'user@example.test',
          'password': 'secret',
          '_csrf': csrf,
        },
        headers: <String, List<String>>{
          HttpHeaders.cookieHeader: <String>[_cookie(initialCookie)],
        },
      );
      login.assertStatus(HttpStatus.ok);
      final cookie = login.cookie('test_session')!;

      final forbiddenOrganization = await client.get(
        '/auth/scim/connections?organizationId=organization-b',
        headers: <String, List<String>>{
          HttpHeaders.cookieHeader: <String>[_cookie(cookie)],
        },
      );
      forbiddenOrganization.assertStatus(HttpStatus.unauthorized);

      final body = <String, Object?>{
        'organizationId': 'organization-a',
        'name': 'Acme Directory',
        'provisioningDomainId': 'employees',
        'scopes': <String>['usersWrite', 'groupsRead'],
        'credentialName': 'Primary',
        'idempotencyKey': 'create-acme',
        '_csrf': csrf,
      };
      final rejectedCsrf = await client.postJson(
        '/auth/scim/connections/create',
        <String, Object?>{...body, '_csrf': 'wrong'},
        headers: <String, List<String>>{
          HttpHeaders.cookieHeader: <String>[_cookie(cookie)],
        },
      );
      rejectedCsrf.assertStatus(HttpStatus.forbidden);

      final created = await client.postJson(
        '/auth/scim/connections/create',
        body,
        headers: <String, List<String>>{
          HttpHeaders.cookieHeader: <String>[_cookie(cookie)],
        },
      );
      created.assertStatus(HttpStatus.ok);
      final createdJson = created.json();
      final connection = createdJson['connection'] as Map<String, dynamic>;
      final issuance = createdJson['issuance'] as Map<String, dynamic>;
      expect(connection['organizationId'], 'organization-a');
      expect(connection['state'], 'active');
      expect(issuance['secret'], startsWith('rscim.'));
      expect(issuance['replayed'], isFalse);

      final replay = await client.postJson(
        '/auth/scim/connections/create',
        body,
        headers: <String, List<String>>{
          HttpHeaders.cookieHeader: <String>[_cookie(cookie)],
        },
      );
      replay.assertStatus(HttpStatus.ok);
      expect(replay.json()['connection']['id'], connection['id']);
      expect(replay.json()['issuance']['replayed'], isTrue);
      expect(replay.json()['issuance'], isNot(contains('secret')));

      final listed = await client.get(
        '/auth/scim/connections?organizationId=organization-a&limit=10&offset=0',
        headers: <String, List<String>>{
          HttpHeaders.cookieHeader: <String>[_cookie(cookie)],
        },
      );
      listed.assertStatus(HttpStatus.ok);
      expect(listed.json()['total'], 1);

      final disabled = await client.postJson(
        '/auth/scim/connections/disable',
        <String, Object?>{
          'organizationId': 'organization-a',
          'connectionId': connection['id'],
          '_csrf': csrf,
        },
        headers: <String, List<String>>{
          HttpHeaders.cookieHeader: <String>[_cookie(cookie)],
        },
      );
      disabled.assertStatus(HttpStatus.ok);
      expect(disabled.json()['state'], 'disabled');
      expect(
        await AuthScimManagedBearerTokenResolver<Object>(
          store: store,
          clock: () => DateTime.utc(2030, 1, 1, 0, 1),
        ).resolve(
          AuthScimBearerTokenRequest<Object>(
            context: Object(),
            token: issuance['secret'] as String,
          ),
        ),
        isNull,
      );
    },
  );
}

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
