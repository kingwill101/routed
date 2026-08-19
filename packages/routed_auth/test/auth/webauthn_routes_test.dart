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

String _cookieHeader(Cookie cookie) => '${cookie.name}=${cookie.value}';

void main() {
  test(
    'WebAuthn feature routes share session and browser protections',
    () async {
      final user = AuthUser(
        id: 'user-1',
        email: 'user@example.com',
        name: 'Example User',
      );
      final store = InMemoryAuthStore();
      await store.users.create(user);
      final webAuthnProvider = WebAuthnProvider(
        getUserInfo: (_, _, _) => null,
        getRelyingParty: (_, _) => const WebAuthnRelyingParty(
          id: 'localhost',
          name: 'Local test',
          origin: 'http://localhost',
        ),
      );
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            CredentialsProvider(authorize: (_, _, _) => user),
            webAuthnProvider,
          ],
          features: [
            WebAuthnFeature<EngineContext>(provider: webAuthnProvider),
          ],
          enforceCsrf: false,
        ),
      );
      final engine = _engine(manager);
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);

      final csrfResponse = await client.get('/auth/csrf');
      final csrf = csrfResponse.json()['csrfToken'] as String;
      final initialCookie = csrfResponse.cookie('test_session');
      expect(initialCookie, isNotNull);
      final signIn = await client.postJson(
        '/auth/signin/credentials',
        <String, dynamic>{
          'email': user.email,
          'password': 'secret',
          '_csrf': csrf,
        },
        headers: <String, List<String>>{
          HttpHeaders.cookieHeader: [_cookieHeader(initialCookie!)],
        },
      );
      signIn.assertStatus(HttpStatus.ok);
      final sessionCookie = signIn.cookie('test_session');
      expect(sessionCookie, isNotNull);
      final sessionHeaders = <String, List<String>>{
        HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
      };

      final options = await client.postJson(
        '/auth/webauthn/register/options',
        const <String, dynamic>{},
        headers: sessionHeaders,
      );
      options.assertStatus(HttpStatus.ok);
      expect(options.json()['challenge'], isA<String>());
      expect(options.json()['rp']['id'], 'localhost');

      final list = await client.get(
        '/auth/webauthn/credentials',
        headers: sessionHeaders,
      );
      list.assertStatus(HttpStatus.ok);
      expect(list.json()['credentials'], isEmpty);

      await store.webAuthnAuthenticators.create(
        WebAuthnAuthenticator(
          credentialId: 'credential-1',
          publicKey: 'cose-key',
          counter: 0,
          userId: user.id,
          createdAt: DateTime.utc(2026, 1, 1),
          name: 'Old name',
        ),
      );
      final renamed = await client.postJson(
        '/auth/webauthn/credentials/rename',
        <String, dynamic>{
          'credentialId': 'credential-1',
          'name': 'New name',
        },
        headers: sessionHeaders,
      );
      renamed.assertStatus(HttpStatus.ok);
      expect(renamed.json()['credential']['name'], 'New name');

      final unauthenticated = TestClient(RoutedRequestHandler(engine));
      addTearDown(unauthenticated.close);
      final rejected = await unauthenticated.postJson(
        '/auth/webauthn/register/options',
        const <String, dynamic>{},
      );
      rejected.assertStatus(HttpStatus.unauthorized);
      expect(rejected.json()['error'], 'unauthorized');

      final crossSite = await client.postJson(
        '/auth/webauthn/register/options',
        const <String, dynamic>{},
        headers: <String, List<String>>{
          ...sessionHeaders,
          'Origin': ['https://evil.example'],
        },
      );
      crossSite.assertStatus(HttpStatus.forbidden);
      expect(crossSite.json()['error'], 'invalid_origin');
    },
  );
}
