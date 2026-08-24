import 'dart:convert';
import 'dart:io' show SameSite;

import 'package:routed_auth/routed_auth.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_sessions/routed_sessions.dart';

/// Session cookie used by [createAuthRuntimeConformanceEngine].
const authRuntimeConformanceCookieName = 'runtime_auth_session';

/// User identifier returned by the conformance credentials provider.
const authRuntimeConformanceUserId = 'runtime-user-1';

/// Email accepted by the conformance credentials provider.
const authRuntimeConformanceEmail = 'runtime@example.test';

/// Password accepted by the conformance credentials provider.
const authRuntimeConformancePassword = 'correct-horse-battery-staple';

/// Sensitive marker used to verify that host errors do not leak details.
const authRuntimeConformanceFailureMarker = '/srv/secrets/runtime-auth.key';

/// A framework-neutral HTTP request issued by the auth runtime conformance test.
final class AuthRuntimeConformanceRequest {
  /// Creates a request for a host transport adapter.
  const AuthRuntimeConformanceRequest({
    required this.method,
    required this.path,
    this.headers = const <String, List<String>>{},
    this.body,
  });

  /// HTTP method.
  final String method;

  /// Origin-relative request path.
  final String path;

  /// Request headers, preserving repeated values.
  final Map<String, List<String>> headers;

  /// Optional UTF-8 request body.
  final String? body;
}

/// A framework-neutral response returned by a host transport adapter.
final class AuthRuntimeConformanceResponse {
  /// Creates a captured response.
  const AuthRuntimeConformanceResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  /// HTTP response status.
  final int statusCode;

  /// Response headers, preserving repeated values.
  final Map<String, List<String>> headers;

  /// UTF-8 response body.
  final String body;

  /// Decodes [body] as JSON, or returns `null` for an empty body.
  Object? get json => body.trim().isEmpty ? null : jsonDecode(body);

  /// Returns all values for [name] using case-insensitive matching.
  List<String> headerValues(String name) {
    final lowerName = name.toLowerCase();
    return headers.entries
        .where((entry) => entry.key.toLowerCase() == lowerName)
        .expand((entry) => entry.value)
        .toList(growable: false);
  }
}

/// Sends one request through the host transport under test.
typedef AuthRuntimeConformanceSend =
    Future<AuthRuntimeConformanceResponse> Function(
      AuthRuntimeConformanceRequest request,
    );

/// A failed auth runtime conformance assertion.
final class AuthRuntimeConformanceFailure implements Exception {
  /// Creates a failure for a stable [caseId].
  const AuthRuntimeConformanceFailure({
    required this.caseId,
    required this.message,
  });

  /// Stable machine-readable identifier for the failed behavior.
  final String caseId;

  /// Human-readable failure detail.
  final String message;

  /// Returns a stable description containing the failed case identifier.
  @override
  String toString() => 'AuthRuntimeConformanceFailure($caseId): $message';
}

/// Creates the opinionated engine fixture used by
/// [verifyAuthRuntimeConformance].
///
/// The fixture enables credential sign-in, cookie-backed sessions, CSRF and
/// browser-origin protection. Its credential callback also has a deliberate
/// failure path used to confirm that transports sanitize internal errors.
Engine createAuthRuntimeConformanceEngine() {
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
              throw StateError(authRuntimeConformanceFailureMarker);
            }
            if (identifier != authRuntimeConformanceEmail ||
                credentials.password != authRuntimeConformancePassword) {
              return null;
            }
            return AuthUser(
              id: authRuntimeConformanceUserId,
              email: authRuntimeConformanceEmail,
              name: 'Runtime User',
            );
          },
        ),
      ],
      cookiePolicy: AuthCookiePolicy.development,
    ),
  );
  final sessionConfig = SessionConfig.cookie(
    appKey: 'base64:$sessionKey',
    cookieName: authRuntimeConformanceCookieName,
    options: SessionOptions(
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

/// Verifies auth behavior through an arbitrary HTTP host transport.
///
/// This utility intentionally has no dependency on `package:test`. Test suites
/// can call it from any test framework and treat an
/// [AuthRuntimeConformanceFailure] as a failed assertion.
Future<void> verifyAuthRuntimeConformance({
  required Uri origin,
  required AuthRuntimeConformanceSend send,
  bool sendValidOriginHeader = true,
}) async {
  final validOriginHeader = sendValidOriginHeader ? origin.toString() : null;
  final csrfResponse = await send(
    const AuthRuntimeConformanceRequest(method: 'GET', path: '/auth/csrf'),
  );
  _check(
    csrfResponse.statusCode == 200,
    'csrf.issue',
    'Expected status 200, received ${csrfResponse.statusCode}.',
  );
  final csrfBody = _jsonObject(csrfResponse, 'csrf.issue');
  final csrfValue = csrfBody['csrfToken'];
  final csrf = switch (csrfValue) {
    final String value when value.isNotEmpty => value,
    _ => throw const AuthRuntimeConformanceFailure(
      caseId: 'csrf.issue',
      message: 'Expected a non-empty csrfToken.',
    ),
  };

  final initialSetCookie = _setCookieFor(
    csrfResponse,
    authRuntimeConformanceCookieName,
  );
  final lowerCookie = initialSetCookie.toLowerCase();
  _check(
    lowerCookie.contains('httponly'),
    'cookie.policy',
    'Session cookie must be HttpOnly.',
  );
  _check(
    lowerCookie.contains('samesite=lax'),
    'cookie.policy',
    'Session cookie must use SameSite=Lax.',
  );
  _check(
    lowerCookie.contains('path=/'),
    'cookie.policy',
    'Session cookie must use Path=/.',
  );
  _check(
    !lowerCookie.contains('secure'),
    'cookie.policy',
    'Development fixture cookie must not be Secure.',
  );
  var cookie = _cookiePair(initialSetCookie);

  final invalidOrigin = await send(
    AuthRuntimeConformanceRequest(
      method: 'POST',
      path: '/auth/signin/credentials',
      headers: _requestHeaders(
        cookie: cookie,
        origin: 'https://attacker.example',
      ),
      body: _credentialsBody(csrf: csrf),
    ),
  );
  _expectError(
    invalidOrigin,
    caseId: 'browser.invalid-origin',
    statusCode: 403,
    error: 'invalid_origin',
  );

  final crossSite = await send(
    AuthRuntimeConformanceRequest(
      method: 'POST',
      path: '/auth/signin/credentials',
      headers: _requestHeaders(cookie: cookie, fetchSite: 'cross-site'),
      body: _credentialsBody(csrf: csrf),
    ),
  );
  _expectError(
    crossSite,
    caseId: 'browser.cross-site',
    statusCode: 403,
    error: 'cross_site_request',
  );

  final invalidCsrf = await send(
    AuthRuntimeConformanceRequest(
      method: 'POST',
      path: '/auth/signin/credentials',
      headers: _requestHeaders(cookie: cookie, origin: validOriginHeader),
      body: _credentialsBody(csrf: 'invalid'),
    ),
  );
  _expectError(
    invalidCsrf,
    caseId: 'csrf.reject-invalid',
    statusCode: 403,
    error: 'invalid_csrf',
  );

  final signIn = await send(
    AuthRuntimeConformanceRequest(
      method: 'POST',
      path: '/auth/signin/credentials',
      headers: _requestHeaders(cookie: cookie, origin: validOriginHeader),
      body: _credentialsBody(csrf: csrf),
    ),
  );
  _check(
    signIn.statusCode == 200,
    'credentials.sign-in',
    'Expected status 200, received ${signIn.statusCode}: ${signIn.body}',
  );
  final signInBody = _jsonObject(signIn, 'credentials.sign-in');
  _check(
    _userId(signInBody) == authRuntimeConformanceUserId,
    'credentials.sign-in',
    'Sign-in response did not contain the conformance user.',
  );
  final updatedSetCookie = _optionalSetCookieFor(
    signIn,
    authRuntimeConformanceCookieName,
  );
  if (updatedSetCookie != null) cookie = _cookiePair(updatedSetCookie);

  final session = await send(
    AuthRuntimeConformanceRequest(
      method: 'GET',
      path: '/auth/session',
      headers: <String, List<String>>{
        'cookie': <String>[cookie],
      },
    ),
  );
  _check(
    session.statusCode == 200,
    'session.read',
    'Expected status 200, received ${session.statusCode}.',
  );
  final sessionBody = _jsonObject(session, 'session.read');
  _check(
    _userId(sessionBody) == authRuntimeConformanceUserId,
    'session.read',
    'Session response did not preserve the authenticated user.',
  );

  final freshCsrf = await send(
    AuthRuntimeConformanceRequest(
      method: 'GET',
      path: '/auth/csrf',
      headers: <String, List<String>>{
        'cookie': <String>[cookie],
      },
    ),
  );
  _check(
    freshCsrf.statusCode == 200,
    'error.sanitization',
    'Could not refresh the CSRF token before the failure request.',
  );
  final failureCsrf = _jsonObject(freshCsrf, 'error.sanitization')['csrfToken'];
  _check(
    failureCsrf is String && failureCsrf.isNotEmpty,
    'error.sanitization',
    'Expected a fresh CSRF token.',
  );
  final failure = await send(
    AuthRuntimeConformanceRequest(
      method: 'POST',
      path: '/auth/signin/credentials',
      headers: _requestHeaders(cookie: cookie, origin: validOriginHeader),
      body: jsonEncode(<String, Object?>{
        'email': 'explode@example.test',
        'password': authRuntimeConformancePassword,
        '_csrf': failureCsrf,
      }),
    ),
  );
  _check(
    failure.statusCode == 500,
    'error.sanitization',
    'Expected status 500, received ${failure.statusCode}.',
  );
  _check(
    !failure.body.contains(authRuntimeConformanceFailureMarker) &&
        !failure.body.contains('/srv/secrets'),
    'error.sanitization',
    'Internal error details leaked into the response body.',
  );
  _check(
    failure.body.toLowerCase().contains('unexpected error'),
    'error.sanitization',
    'Expected the generic unexpected-error response.',
  );
}

Map<String, Object?> _jsonObject(
  AuthRuntimeConformanceResponse response,
  String caseId,
) {
  Object? value;
  try {
    value = response.json;
  } on FormatException catch (error) {
    throw AuthRuntimeConformanceFailure(
      caseId: caseId,
      message: 'Expected a JSON object: $error',
    );
  }
  _check(value is Map<String, Object?>, caseId, 'Expected a JSON object.');
  return value! as Map<String, Object?>;
}

String? _userId(Map<String, Object?> body) {
  final user = body['user'];
  if (user is! Map<String, Object?>) return null;
  final id = user['id'];
  return id is String ? id : null;
}

void _expectError(
  AuthRuntimeConformanceResponse response, {
  required String caseId,
  required int statusCode,
  required String error,
}) {
  _check(
    response.statusCode == statusCode,
    caseId,
    'Expected status $statusCode, received ${response.statusCode}.',
  );
  final body = _jsonObject(response, caseId);
  _check(
    body['error'] == error,
    caseId,
    'Expected error "$error", received "${body['error']}".',
  );
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
  'email': authRuntimeConformanceEmail,
  'password': authRuntimeConformancePassword,
  '_csrf': csrf,
});

String _setCookieFor(AuthRuntimeConformanceResponse response, String name) {
  final value = _optionalSetCookieFor(response, name);
  _check(
    value != null,
    'cookie.policy',
    'Expected a Set-Cookie header for $name.',
  );
  return value!;
}

String? _optionalSetCookieFor(
  AuthRuntimeConformanceResponse response,
  String name,
) {
  final prefix = '$name=';
  for (final value in response.headerValues('set-cookie')) {
    if (value.trimLeft().startsWith(prefix)) return value;
  }
  return null;
}

String _cookiePair(String setCookie) => setCookie.split(';').first.trim();

void _check(bool condition, String caseId, String message) {
  if (!condition) {
    throw AuthRuntimeConformanceFailure(caseId: caseId, message: message);
  }
}
