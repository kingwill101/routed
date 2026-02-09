import 'dart:convert';
import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed/session.dart';
import 'package:routed/src/sessions/middleware.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
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
  engine.addGlobalMiddleware(sessionMiddleware());
  AuthRoutes(manager).register(engine.defaultRouter);
  return engine;
}

String _cookieHeader(Cookie cookie) => '${cookie.name}=${cookie.value}';

void main() {
  test('GET sign-in for credentials is rejected', () async {
    final manager = AuthManager(
      AuthOptions(providers: [CredentialsProvider()], enforceCsrf: false),
    );

    final engine = _authEngine(manager);
    await engine.initialize();

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(() async => await client.close());

    final response = await client.get('/auth/signin/credentials');
    response.assertStatus(HttpStatus.methodNotAllowed);
    expect(response.json()['error'], equals('method_not_allowed'));
  });

  test('callbackUrl sanitization ignores external redirects', () async {
    final manager = AuthManager(
      AuthOptions(
        providers: [
          OAuthProvider<Map<String, dynamic>>(
            id: 'oauth',
            name: 'OAuth',
            clientId: 'client-id',
            clientSecret: 'client-secret',
            authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
            tokenEndpoint: Uri.parse('https://auth.test/token'),
            redirectUri: 'https://app.test/auth/callback/oauth',
            profile: (profile) => AuthUser(id: 'user'),
          ),
        ],
      ),
    );

    final engine = _authEngine(manager);
    await engine.initialize();

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(() async => await client.close());

    final response = await client.get(
      '/auth/signin/oauth?callbackUrl=https://evil.test',
    );
    response.assertStatus(HttpStatus.movedTemporarily);
    final location = response.headers[HttpHeaders.locationHeader]!.first;
    final uri = Uri.parse(location);
    expect(uri.queryParameters.containsKey('callbackUrl'), isFalse);
  });

  test('unknown providers return not found responses', () async {
    final manager = AuthManager(
      AuthOptions(providers: [CredentialsProvider()], enforceCsrf: false),
    );

    final engine = _authEngine(manager);
    await engine.initialize();

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(() async => await client.close());

    final signIn = await client.postJson(
      '/auth/signin/missing',
      <String, dynamic>{},
    );
    signIn.assertStatus(HttpStatus.notFound);
    expect(signIn.json()['error'], equals('unknown_provider'));

    final register = await client.postJson(
      '/auth/register/missing',
      <String, dynamic>{},
    );
    register.assertStatus(HttpStatus.notFound);
    expect(register.json()['error'], equals('unknown_provider'));

    final callback = await client.get('/auth/callback/missing');
    callback.assertStatus(HttpStatus.notFound);
    expect(callback.json()['error'], equals('unknown_provider'));
  });

  test('rejects missing OAuth callback code', () async {
    final manager = AuthManager(
      AuthOptions(
        providers: [
          OAuthProvider<Map<String, dynamic>>(
            id: 'oauth',
            name: 'OAuth',
            clientId: 'client-id',
            clientSecret: 'client-secret',
            authorizationEndpoint: Uri.parse('https://auth.test/authorize'),
            tokenEndpoint: Uri.parse('https://auth.test/token'),
            redirectUri: 'https://app.test/auth/callback/oauth',
            profile: (profile) => AuthUser(id: 'user'),
          ),
        ],
      ),
    );

    final engine = _authEngine(manager);
    await engine.initialize();

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(() async => await client.close());

    final response = await client.get('/auth/callback/oauth');
    response.assertStatus(HttpStatus.badRequest);
    expect(response.json()['error'], equals('missing_code'));
  });

  test('rejects missing email verification tokens', () async {
    final manager = AuthManager(
      AuthOptions(
        providers: [EmailProvider(sendVerificationRequest: (_, _, _) async {})],
        enforceCsrf: false,
      ),
    );

    final engine = _authEngine(manager);
    await engine.initialize();

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(() async => await client.close());

    final response = await client.get('/auth/callback/email?email=test');
    response.assertStatus(HttpStatus.badRequest);
    expect(response.json()['error'], equals('missing_token'));
  });

  test('register rejects unsupported providers', () async {
    final manager = AuthManager(
      AuthOptions(
        providers: [EmailProvider(sendVerificationRequest: (_, _, _) async {})],
        enforceCsrf: false,
      ),
    );

    final engine = _authEngine(manager);
    await engine.initialize();

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(() async => await client.close());

    final response = await client.postJson(
      '/auth/register/email',
      <String, dynamic>{},
    );
    response.assertStatus(HttpStatus.badRequest);
    expect(response.json()['error'], equals('unsupported_provider'));
  });

  test('rejects invalid CSRF tokens on sign-in', () async {
    final manager = AuthManager(
      AuthOptions(providers: [CredentialsProvider()], enforceCsrf: true),
    );

    final engine = _authEngine(manager);
    await engine.initialize();

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(() async => await client.close());

    final csrfResponse = await client.get('/auth/csrf');
    final sessionCookie = csrfResponse.cookie('test_session');
    expect(sessionCookie, isNotNull);

    final signIn = await client.postJson(
      '/auth/signin/credentials',
      {'email': 'user@example.com', 'password': 'secret', '_csrf': 'bad'},
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
      },
    );
    signIn.assertStatus(HttpStatus.forbidden);
    expect(signIn.json()['error'], equals('invalid_csrf'));
  });

  test('signout clears JWT cookies', () async {
    final manager = AuthManager(
      AuthOptions(
        providers: [CredentialsProvider()],
        sessionStrategy: AuthSessionStrategy.jwt,
        enforceCsrf: false,
      ),
    );

    final engine = _authEngine(manager);
    await engine.initialize();

    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(() async => await client.close());

    final signOut = await client.postJson('/auth/signout', <String, dynamic>{});
    signOut.assertStatus(HttpStatus.ok);
    final cookie = signOut.cookie(manager.options.jwtOptions.cookieName);
    expect(cookie, isNotNull);
    expect(cookie!.maxAge, equals(0));
  });
}
