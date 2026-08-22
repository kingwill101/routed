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

void main() {
  test(
    'sign-out runs the framework session hooks for built-in routes',
    () async {
      final events = <String>[];
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            CredentialsProvider(
              authorize: (_, _, credentials) =>
                  AuthUser(id: 'hook-user', email: credentials.email),
            ),
          ],
          enforceCsrf: false,
          frameworkSessionHooks: AuthFrameworkSessionHooks<EngineContext>(
            beforeSignOut: (_) => events.add('before'),
            afterSignOut: (context) {
              events.add('after');
              context.response.setCookie(
                'framework_session',
                '',
                maxAge: 0,
                path: '/',
              );
            },
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
      addTearDown(() async => await engine.close());

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      final signIn = await client.postJson(
        '/auth/signin/credentials',
        <String, Object?>{
          'email': 'hook@example.test',
          'password': 'unused-by-test-provider',
        },
      );
      signIn.assertStatus(HttpStatus.ok);

      final signOut = await client.postJson(
        '/auth/signout',
        <String, Object?>{},
      );
      signOut.assertStatus(HttpStatus.ok);
      expect(events, equals(['before', 'after']));
      expect(
        signOut.headers[HttpHeaders.setCookieHeader],
        anyElement(contains('framework_session=;')),
      );
      expect(
        signOut.headers[HttpHeaders.setCookieHeader],
        anyElement(contains('Max-Age=0')),
      );
    },
  );
}
