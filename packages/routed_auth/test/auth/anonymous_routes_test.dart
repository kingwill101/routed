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

    final signedIn = await client.postJson('/auth/sign-in/anonymous', {});
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
    final deleted = await client.postJson(
      '/auth/delete-anonymous-user',
      {'_csrf': csrf.json()['csrfToken']},
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
      },
    );
    deleted.assertStatus(HttpStatus.ok);
    expect(deleted.json()['status'], 'anonymous_deleted');
    expect(await manager.store.users.findById(anonymousId), isNull);
  });
}
