import 'dart:convert';
import 'dart:convert';
import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed/session.dart';
import 'package:routed/src/sessions/middleware.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'package:test/test.dart';

import '../test_engine.dart';

SessionConfig _sessionConfig() {
  final key = base64.encode(List<int>.generate(32, (i) => i + 1));
  return SessionConfig.cookie(
    appKey: 'base64:$key',
    cookieName: 'test_session',
    options: Options(
      path: '/',
      secure: false,
      httpOnly: true,
      sameSite: SameSite.lax,
    ),
  );
}

Engine _authEngine(AuthManager manager) {
  final sessionConfig = _sessionConfig();
  final engine = testEngine(
    config: EngineConfig(
      security: const EngineSecurityFeatures(csrfProtection: false),
    ),
    options: [withSessionConfig(sessionConfig)],
  );
  engine.addGlobalMiddleware(
    sessionMiddleware(
      store: sessionConfig.store,
      name: sessionConfig.cookieName,
    ),
  );
  engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());
  AuthRoutes(manager).register(engine.defaultRouter);
  return engine;
}

String _cookieHeader(Cookie cookie) => '${cookie.name}=${cookie.value}';

void main() {
  group('Auth callbacks and events', () {
    test('signIn callback can deny sign-in', () async {
      final manager = AuthManager(
        AuthOptions(
          providers: [
            CredentialsProvider(
              authorize: (ctx, provider, credentials) async {
                return AuthUser(id: 'user-1', email: credentials.email);
              },
            ),
          ],
          sessionStrategy: AuthSessionStrategy.session,
          enforceCsrf: false,
          callbacks: AuthCallbacks(signIn: _denySignIn),
        ),
      );
      final engine = _authEngine(manager);
      await engine.initialize();

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      final csrfResponse = await client.get('/auth/csrf');
      final csrfToken = csrfResponse.json()['csrfToken'] as String;
      final sessionCookie = csrfResponse.cookie('test_session');
      expect(sessionCookie, isNotNull);

      final signInResponse = await client.postJson(
        '/auth/signin/credentials',
        {'email': 'user@example.com', 'password': 'secret', '_csrf': csrfToken},
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
        },
      );
      signInResponse.assertStatus(HttpStatus.unauthorized);
      expect(signInResponse.json()['error'], equals('sign_in_blocked'));
    });

    test('session callback decorates payload', () async {
      final manager = AuthManager(
        AuthOptions(
          providers: [
            CredentialsProvider(
              authorize: (ctx, provider, credentials) async {
                return AuthUser(id: 'user-1', email: credentials.email);
              },
            ),
          ],
          sessionStrategy: AuthSessionStrategy.session,
          enforceCsrf: false,
          callbacks: AuthCallbacks(
            session: (context) async {
              return {...context.payload, 'note': 'custom'};
            },
          ),
        ),
      );
      final engine = _authEngine(manager);
      await engine.initialize();

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      final csrfResponse = await client.get('/auth/csrf');
      final csrfToken = csrfResponse.json()['csrfToken'] as String;
      final sessionCookie = csrfResponse.cookie('test_session');
      expect(sessionCookie, isNotNull);

      final signInResponse = await client.postJson(
        '/auth/signin/credentials',
        {'email': 'user@example.com', 'password': 'secret', '_csrf': csrfToken},
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
        },
      );
      signInResponse.assertStatus(HttpStatus.ok);
      expect(signInResponse.json()['note'], equals('custom'));

      final authCookie = signInResponse.cookie('test_session');
      expect(authCookie, isNotNull);

      final sessionResponse = await client.get(
        '/auth/session',
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(authCookie!)],
        },
      );
      sessionResponse.assertStatus(HttpStatus.ok);
      expect(sessionResponse.json()['note'], equals('custom'));
    });

    test('jwt callback augments claims', () async {
      const jwtSecret = 'jwt-secret';
      final manager = AuthManager(
        AuthOptions(
          providers: [
            CredentialsProvider(
              authorize: (ctx, provider, credentials) async {
                return AuthUser(id: 'user-1', email: credentials.email);
              },
            ),
          ],
          sessionStrategy: AuthSessionStrategy.jwt,
          jwtOptions: const JwtSessionOptions(secret: jwtSecret),
          enforceCsrf: false,
          callbacks: AuthCallbacks(
            jwt: (context) async {
              return {...context.token, 'custom': 'value'};
            },
          ),
        ),
      );
      final engine = _authEngine(manager);
      await engine.initialize();

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      final csrfResponse = await client.get('/auth/csrf');
      final csrfToken = csrfResponse.json()['csrfToken'] as String;
      final sessionCookie = csrfResponse.cookie('test_session');
      expect(sessionCookie, isNotNull);

      final signInResponse = await client.postJson(
        '/auth/signin/credentials',
        {'email': 'user@example.com', 'password': 'secret', '_csrf': csrfToken},
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
        },
      );
      signInResponse.assertStatus(HttpStatus.ok);

      final jwtCookie = signInResponse.cookie(
        manager.options.jwtOptions.cookieName,
      );
      expect(jwtCookie, isNotNull);

      final verifier = JwtVerifier(
        options: manager.options.jwtOptions.toVerifierOptions(),
      );
      final payload = await verifier.verifyToken(jwtCookie!.value);
      expect(payload.claims['custom'], equals('value'));
    });

    test('events fire on sign-in and sign-out', () async {
      final events = <String>[];
      final manager = AuthManager(
        AuthOptions(
          providers: [
            CredentialsProvider(
              authorize: (ctx, provider, credentials) async {
                return AuthUser(id: 'user-1', email: credentials.email);
              },
            ),
          ],
          sessionStrategy: AuthSessionStrategy.session,
          enforceCsrf: false,
        ),
      );
      final engine = _authEngine(manager);
      await engine.initialize();

      final eventManager = await engine.container.make<EventManager>();
      eventManager.listen<AuthSignInEvent>(
        (event) => events.add('sign_in:${event.user.id}'),
      );
      eventManager.listen<AuthSignOutEvent>(
        (event) => events.add('sign_out:${event.user?.id}'),
      );
      eventManager.listen<AuthSessionEvent>((event) => events.add('session'));

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(() async => await client.close());

      final csrfResponse = await client.get('/auth/csrf');
      final csrfToken = csrfResponse.json()['csrfToken'] as String;
      final sessionCookie = csrfResponse.cookie('test_session');
      expect(sessionCookie, isNotNull);

      final signInResponse = await client.postJson(
        '/auth/signin/credentials',
        {'email': 'user@example.com', 'password': 'secret', '_csrf': csrfToken},
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
        },
      );
      signInResponse.assertStatus(HttpStatus.ok);

      final authCookie = signInResponse.cookie('test_session');
      expect(authCookie, isNotNull);

      final signOutResponse = await client.postJson(
        '/auth/signout',
        {'_csrf': csrfToken},
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(authCookie!)],
        },
      );
      signOutResponse.assertStatus(HttpStatus.ok);

      expect(events, contains('sign_in:user-1'));
      expect(events, contains('sign_out:user-1'));
      expect(events, contains('session'));
    });
  });
}

AuthSignInResult _denySignIn(AuthSignInCallbackContext context) {
  return const AuthSignInResult.deny();
}
