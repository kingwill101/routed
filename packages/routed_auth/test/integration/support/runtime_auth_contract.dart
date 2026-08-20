import 'dart:convert';
import 'dart:io' show SameSite;

import 'package:routed_auth/routed_auth.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:test/test.dart';

const runtimeAuthCookieName = 'runtime_auth_session';
const runtimeAuthUserId = 'runtime-user-1';
const runtimeAuthEmail = 'runtime@example.test';
const runtimeAuthPassword = 'correct-horse-battery-staple';
const runtimeAuthFailureMarker = '/srv/secrets/runtime-auth.key';

final class RuntimeAuthRequest {
  const RuntimeAuthRequest({
    required this.method,
    required this.path,
    this.headers = const <String, List<String>>{},
    this.body,
  });

  final String method;
  final String path;
  final Map<String, List<String>> headers;
  final String? body;
}

final class RuntimeAuthResponse {
  const RuntimeAuthResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, List<String>> headers;
  final String body;

  Object? get json => body.trim().isEmpty ? null : jsonDecode(body);

  List<String> headerValues(String name) {
    final lowerName = name.toLowerCase();
    return headers.entries
        .where((entry) => entry.key.toLowerCase() == lowerName)
        .expand((entry) => entry.value)
        .toList(growable: false);
  }
}

typedef RuntimeAuthSend =
    Future<RuntimeAuthResponse> Function(RuntimeAuthRequest request);

Engine createRuntimeAuthEngine() {
  final sessionKey = base64.encode(
    List<int>.generate(32, (index) => index + 1),
  );
  final manager = AuthManager(
    AuthOptions<EngineContext>(
      store: InMemoryAuthStore(),
      storeMode: AuthStoreMode.ephemeral,
      providers: [
        CredentialsProvider(
          authorize: (_, _, credentials) async {
            final identifier = credentials.email ?? credentials.username;
            if (identifier == 'explode@example.test') {
              throw StateError(runtimeAuthFailureMarker);
            }
            if (identifier != runtimeAuthEmail ||
                credentials.password != runtimeAuthPassword) {
              return null;
            }
            return AuthUser(
              id: runtimeAuthUserId,
              email: runtimeAuthEmail,
              name: 'Runtime User',
            );
          },
        ),
      ],
      sessionStrategy: AuthSessionStrategy.session,
      enforceCsrf: true,
      cookiePolicy: AuthCookiePolicy.development,
    ),
  );
  final sessionConfig = SessionConfig.cookie(
    appKey: 'base64:$sessionKey',
    cookieName: runtimeAuthCookieName,
    options: SessionOptions(
      path: '/',
      secure: false,
      httpOnly: true,
      sameSite: SameSite.lax,
    ),
  );
  final engine = Engine(
    config: EngineConfig(
      security: const EngineSecurityFeatures(csrfProtection: false),
    ),
    providers: [
      ...Engine.defaultProviders,
      RoutedSessionsProvider(sessionConfig),
    ],
  );
  engine.addGlobalMiddleware(sessionMiddleware());
  engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());
  AuthRoutes(manager).register(engine.defaultRouter);
  return engine;
}

Future<void> verifyRuntimeAuthContract({
  required Uri origin,
  required RuntimeAuthSend send,
  bool sendValidOriginHeader = true,
}) async {
  final validOriginHeader = sendValidOriginHeader ? origin.toString() : null;
  final csrfResponse = await send(
    const RuntimeAuthRequest(method: 'GET', path: '/auth/csrf'),
  );
  expect(csrfResponse.statusCode, 200);
  final csrfBody = csrfResponse.json as Map<String, dynamic>;
  final csrf = csrfBody['csrfToken'] as String;
  expect(csrf, isNotEmpty);

  final initialSetCookie = _setCookieFor(csrfResponse, runtimeAuthCookieName);
  expect(initialSetCookie, contains('HttpOnly'));
  expect(initialSetCookie.toLowerCase(), contains('samesite=lax'));
  expect(initialSetCookie.toLowerCase(), contains('path=/'));
  expect(initialSetCookie.toLowerCase(), isNot(contains('secure')));
  var cookie = _cookiePair(initialSetCookie);

  final invalidOrigin = await send(
    RuntimeAuthRequest(
      method: 'POST',
      path: '/auth/signin/credentials',
      headers: _requestHeaders(
        cookie: cookie,
        origin: 'https://attacker.example',
      ),
      body: _credentialsBody(csrf: csrf),
    ),
  );
  expect(invalidOrigin.statusCode, 403);
  expect(
    (invalidOrigin.json as Map<String, dynamic>)['error'],
    'invalid_origin',
  );

  final crossSite = await send(
    RuntimeAuthRequest(
      method: 'POST',
      path: '/auth/signin/credentials',
      headers: _requestHeaders(cookie: cookie, fetchSite: 'cross-site'),
      body: _credentialsBody(csrf: csrf),
    ),
  );
  expect(crossSite.statusCode, 403);
  expect(
    (crossSite.json as Map<String, dynamic>)['error'],
    'cross_site_request',
  );

  final invalidCsrf = await send(
    RuntimeAuthRequest(
      method: 'POST',
      path: '/auth/signin/credentials',
      headers: _requestHeaders(cookie: cookie, origin: validOriginHeader),
      body: _credentialsBody(csrf: 'invalid'),
    ),
  );
  expect(invalidCsrf.statusCode, 403);
  expect((invalidCsrf.json as Map<String, dynamic>)['error'], 'invalid_csrf');

  final signIn = await send(
    RuntimeAuthRequest(
      method: 'POST',
      path: '/auth/signin/credentials',
      headers: _requestHeaders(cookie: cookie, origin: validOriginHeader),
      body: _credentialsBody(csrf: csrf),
    ),
  );
  expect(signIn.statusCode, 200, reason: signIn.body);
  final signInBody = signIn.json as Map<String, dynamic>;
  expect((signInBody['user'] as Map<String, dynamic>)['id'], runtimeAuthUserId);
  final updatedSetCookie = _optionalSetCookieFor(signIn, runtimeAuthCookieName);
  if (updatedSetCookie != null) cookie = _cookiePair(updatedSetCookie);

  final session = await send(
    RuntimeAuthRequest(
      method: 'GET',
      path: '/auth/session',
      headers: <String, List<String>>{
        'cookie': <String>[cookie],
      },
    ),
  );
  expect(session.statusCode, 200);
  final sessionBody = session.json as Map<String, dynamic>;
  expect(
    (sessionBody['user'] as Map<String, dynamic>)['id'],
    runtimeAuthUserId,
  );

  final freshCsrf = await send(
    RuntimeAuthRequest(
      method: 'GET',
      path: '/auth/csrf',
      headers: <String, List<String>>{
        'cookie': <String>[cookie],
      },
    ),
  );
  final failureCsrf =
      (freshCsrf.json as Map<String, dynamic>)['csrfToken'] as String;
  final failure = await send(
    RuntimeAuthRequest(
      method: 'POST',
      path: '/auth/signin/credentials',
      headers: _requestHeaders(cookie: cookie, origin: validOriginHeader),
      body: jsonEncode(<String, Object?>{
        'email': 'explode@example.test',
        'password': runtimeAuthPassword,
        '_csrf': failureCsrf,
      }),
    ),
  );
  expect(failure.statusCode, 500);
  expect(failure.body, isNot(contains(runtimeAuthFailureMarker)));
  expect(failure.body, isNot(contains('/srv/secrets')));
  expect(failure.body.toLowerCase(), contains('unexpected error'));
}

Map<String, List<String>> _requestHeaders({
  required String cookie,
  String? origin,
  String? fetchSite,
}) => <String, List<String>>{
  'content-type': const <String>['application/json'],
  'cookie': <String>[cookie],
  if (origin != null) 'origin': <String>[origin],
  if (fetchSite != null) 'sec-fetch-site': <String>[fetchSite],
};

String _credentialsBody({required String csrf}) => jsonEncode(<String, Object?>{
  'email': runtimeAuthEmail,
  'password': runtimeAuthPassword,
  '_csrf': csrf,
});

String _setCookieFor(RuntimeAuthResponse response, String name) {
  final value = _optionalSetCookieFor(response, name);
  expect(value, isNotNull, reason: 'Expected a Set-Cookie header for $name');
  return value!;
}

String? _optionalSetCookieFor(RuntimeAuthResponse response, String name) {
  final prefix = '$name=';
  for (final value in response.headerValues('set-cookie')) {
    if (value.trimLeft().startsWith(prefix)) return value;
  }
  return null;
}

String _cookiePair(String setCookie) => setCookie.split(';').first.trim();
