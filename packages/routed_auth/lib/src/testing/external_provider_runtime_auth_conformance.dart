import 'dart:convert';
import 'dart:io' show SameSite;

import 'package:routed_auth/routed_auth.dart';
import 'package:routed_auth/src/testing/runtime_auth_conformance.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:server_auth/testing.dart';

/// Host session cookie used by the external-provider conformance fixture.
const authExternalProviderRuntimeCookieName = 'runtime_external_auth_session';

/// OIDC provider ID used by the external-provider conformance fixture.
const authExternalProviderRuntimeOidcProviderId = 'runtime-oidc';

/// Custom callback provider ID used by the external-provider fixture.
const authExternalProviderRuntimeCallbackProviderId = 'runtime-callback';

/// Sensitive marker that deterministic provider failures must never expose.
const authExternalProviderRuntimeFailureMarker =
    '/srv/secrets/runtime-provider-client.key';

const _username = 'external.runtime';
const _email = 'external-runtime@example.test';
const _password = 'external-runtime-password-123';
const _oidcClientId = 'runtime-client';
const _oidcSecret = 'runtime-oidc-signing-secret';
const _oidcIssuer = 'https://provider.runtime.test';
const _jwtCookieName = 'runtime_auth_token';

/// Creates an auth engine backed only by deterministic external providers.
///
/// Provider token and key requests are handled by an in-process scripted HTTP
/// client. The fixture never reads live secrets or opens a provider network
/// connection.
Engine createAuthExternalProviderRuntimeConformanceEngine({
  AuthSessionStrategy sessionStrategy = AuthSessionStrategy.session,
}) {
  final providerClient = _createProviderClient();
  final manager = AuthManager(
    AuthOptions<EngineContext>(
      store: InMemoryAuthStore(),
      storeMode: AuthStoreMode.ephemeral,
      providers: <AuthProvider>[
        _createOidcProvider(),
        _RuntimeCallbackProvider(),
      ],
      plugins: <AuthServerPlugin<EngineContext>>[
        UsernamePlugin<EngineContext>(),
      ],
      passwordHasher: const _ConformancePasswordHasher(),
      sessionStrategy: sessionStrategy,
      jwtOptions: const JwtSessionOptions(
        secret: 'runtime-jwt-secret-with-at-least-32-bytes',
        cookieName: _jwtCookieName,
        secure: false,
      ),
      httpClient: providerClient,
      cookiePolicy: AuthCookiePolicy.development,
    ),
  );
  final sessionKey = base64.encode(
    List<int>.generate(32, (index) => 127 - index),
  );
  final engine = Engine(
    config: EngineConfig(
      security: const EngineSecurityFeatures(csrfProtection: false),
    ),
    providers: <ServiceProvider>[
      ...Engine.defaultProviders,
      RoutedSessionsProvider(
        SessionConfig.cookie(
          appKey: 'base64:$sessionKey',
          cookieName: authExternalProviderRuntimeCookieName,
          options: SessionOptions(
            secure: false,
            httpOnly: true,
            sameSite: SameSite.lax,
          ),
        ),
      ),
    ],
  );
  engine.addGlobalMiddleware(sessionMiddleware());
  engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());
  AuthRoutes(manager).register(engine.defaultRouter);
  return engine;
}

/// Verifies deterministic external-provider behavior through one host adapter.
///
/// [send] must target an engine created by
/// [createAuthExternalProviderRuntimeConformanceEngine] with the strategy
/// represented by [expectJwt]. This helper has no dependency on `package:test`
/// or browser interoperability libraries.
Future<void> verifyAuthExternalProviderRuntimeConformance({
  required Uri origin,
  required AuthRuntimeConformanceSend send,
  required bool expectJwt,
}) async {
  final existingUserId = await _seedExistingUser(send, origin.toString());
  final primary = await _startOidc(send);
  final sessionOnlyCookie = _cookieNamed(
    primary.cookieHeader,
    authExternalProviderRuntimeCookieName,
  );
  _check(
    sessionOnlyCookie != null,
    'oidc.start.browser-cookie',
    'OIDC start did not issue the host session cookie.',
  );

  // A missing auxiliary state cookie is intentionally supported by the
  // framework-session fallback. To test browser binding, use the framework
  // cookie from a genuinely different browser session instead.
  final otherBrowser = await _startOidc(send);
  final otherSessionCookie = _cookieNamed(
    otherBrowser.cookieHeader,
    authExternalProviderRuntimeCookieName,
  );
  _check(
    otherSessionCookie != null,
    'oidc.start.other-browser-cookie',
    'The second OIDC browser did not issue the host session cookie.',
  );

  final crossBrowser = await _finishOidc(
    send,
    start: primary,
    cookie: otherSessionCookie!,
    state: primary.state,
    variant: 'verified',
  );
  _expectProviderError(
    crossBrowser,
    caseId: 'oidc.callback.browser-binding',
    error: 'invalid_state',
  );

  final tampered = await _finishOidc(
    send,
    start: primary,
    cookie: primary.cookieHeader,
    state: '${primary.state}x',
    variant: 'verified',
  );
  _expectProviderError(
    tampered,
    caseId: 'oidc.callback.state-tampering',
    error: 'invalid_state',
  );

  final linked = await _finishOidc(
    send,
    start: primary,
    cookie: primary.cookieHeader,
    state: primary.state,
    variant: 'verified',
  );
  _expectStatus(linked, 200, 'oidc.callback.verified-email');
  final linkedBody = _jsonObject(linked, 'oidc.callback.verified-email');
  _check(
    _userField(linkedBody, 'id') == existingUserId,
    'oidc.callback.verified-email',
    'A verified provider email did not reuse the existing account.',
  );
  _check(
    _userField(linkedBody, 'email') == _email,
    'oidc.callback.verified-email',
    'The linked provider user did not retain its verified email.',
  );
  _expectStrategyAndCookie(
    linked,
    linkedBody,
    caseId: 'oidc.callback.host-session',
    expectJwt: expectJwt,
  );

  final replay = await _finishOidc(
    send,
    start: primary,
    cookie: primary.cookieHeader,
    state: primary.state,
    variant: 'verified',
  );
  _expectProviderError(
    replay,
    caseId: 'oidc.callback.replay',
    error: 'invalid_state',
  );

  final unverifiedStart = await _startOidc(send);
  final unverified = await _finishOidc(
    send,
    start: unverifiedStart,
    cookie: unverifiedStart.cookieHeader,
    state: unverifiedStart.state,
    variant: 'unverified',
  );
  _expectStatus(unverified, 200, 'oidc.callback.unverified-email');
  final unverifiedBody = _jsonObject(
    unverified,
    'oidc.callback.unverified-email',
  );
  _check(
    _userField(unverifiedBody, 'id') != existingUserId,
    'oidc.callback.unverified-email',
    'An unverified provider email silently linked an existing account.',
  );
  _check(
    _userField(unverifiedBody, 'email') == null,
    'oidc.callback.unverified-email',
    'An unverified provider email was persisted as trusted identity data.',
  );

  final nonceStart = await _startOidc(send);
  final badNonce = await _finishOidc(
    send,
    start: nonceStart,
    cookie: nonceStart.cookieHeader,
    state: nonceStart.state,
    variant: 'bad-nonce',
  );
  _expectProviderError(
    badNonce,
    caseId: 'oidc.callback.nonce-tampering',
    error: 'oidc_nonce_mismatch',
  );

  final failureStart = await _startOidc(send);
  final providerFailure = await send(
    AuthRuntimeConformanceRequest(
      method: 'GET',
      path: Uri(
        path: '/auth/callback/$authExternalProviderRuntimeOidcProviderId',
        queryParameters: <String, String>{
          'code': 'provider-failure',
          'state': failureStart.state,
        },
      ).toString(),
      headers: <String, List<String>>{
        'cookie': <String>[failureStart.cookieHeader],
      },
    ),
  );
  _expectProviderError(
    providerFailure,
    caseId: 'oidc.callback.provider-failure',
    error: 'token_exchange_failed',
  );

  final safeStart = await _startOidc(send, callbackUrl: '/after-oauth');
  final safeRedirect = await _finishOidc(
    send,
    start: safeStart,
    cookie: safeStart.cookieHeader,
    state: safeStart.state,
    variant: 'verified',
  );
  _expectStatus(safeRedirect, 302, 'oidc.redirect.safe');
  _check(
    _location(safeRedirect) == '/after-oauth',
    'oidc.redirect.safe',
    'A rooted relative provider redirect was not preserved.',
  );
  _expectIssuedAuthCookie(
    safeRedirect,
    caseId: 'oidc.redirect.safe',
    expectJwt: expectJwt,
  );

  for (final unsafe in const <String>[
    'https://attacker.example/steal',
    '//attacker.example/steal',
    'javascript:alert(1)',
    '/safe\r\nlocation:https://attacker.example',
  ]) {
    final start = await _startOidc(send, callbackUrl: unsafe);
    final response = await _finishOidc(
      send,
      start: start,
      cookie: start.cookieHeader,
      state: start.state,
      variant: 'unsafe',
    );
    _expectStatus(response, 200, 'oidc.redirect.unsafe');
    _check(
      _location(response) == null &&
          !response.body.contains('attacker.example') &&
          !response.body.toLowerCase().contains('javascript:'),
      'oidc.redirect.unsafe',
      'An unsafe provider redirect reached the public response.',
    );
  }

  await _verifyCustomCallbackProvider(send, expectJwt: expectJwt);
}

Future<String> _seedExistingUser(
  AuthRuntimeConformanceSend send,
  String origin,
) async {
  final response = await send(
    AuthRuntimeConformanceRequest(
      method: 'POST',
      path: '/auth/username/register',
      headers: _jsonHeaders(origin: origin),
      body: jsonEncode(<String, Object?>{
        'username': _username,
        'email': _email,
        'password': _password,
      }),
    ),
  );
  _expectStatus(response, 200, 'external.seed-user');
  _check(
    !response.body.contains(_password),
    'external.seed-user',
    'The seed credential leaked into the public response.',
  );
  final userId = _userField(_jsonObject(response, 'external.seed-user'), 'id');
  _check(
    userId is String && userId.isNotEmpty,
    'external.seed-user',
    'The seed registration did not return a user ID.',
  );
  return userId! as String;
}

Future<void> _verifyCustomCallbackProvider(
  AuthRuntimeConformanceSend send, {
  required bool expectJwt,
}) async {
  final safe = await send(
    AuthRuntimeConformanceRequest(
      method: 'GET',
      path: Uri(
        path: '/auth/callback/$authExternalProviderRuntimeCallbackProviderId',
        queryParameters: const <String, String>{'redirect': '/after-custom'},
      ).toString(),
    ),
  );
  _expectStatus(safe, 302, 'callback-provider.success');
  _check(
    _location(safe) == '/after-custom',
    'callback-provider.success',
    'The custom callback provider did not preserve its safe redirect.',
  );
  _expectIssuedAuthCookie(
    safe,
    caseId: 'callback-provider.host-session',
    expectJwt: expectJwt,
  );

  final unsafe = await send(
    AuthRuntimeConformanceRequest(
      method: 'GET',
      path: Uri(
        path: '/auth/callback/$authExternalProviderRuntimeCallbackProviderId',
        queryParameters: const <String, String>{
          'redirect': 'https://attacker.example/custom',
        },
      ).toString(),
    ),
  );
  _expectStatus(unsafe, 200, 'callback-provider.redirect');
  _check(
    _location(unsafe) == null && !unsafe.body.contains('attacker.example'),
    'callback-provider.redirect',
    'The custom callback provider emitted an unsafe redirect.',
  );

  for (final outcome in const <String>['failure', 'throw']) {
    final response = await send(
      AuthRuntimeConformanceRequest(
        method: 'GET',
        path: Uri(
          path:
              '/auth/callback/'
              '$authExternalProviderRuntimeCallbackProviderId',
          queryParameters: <String, String>{'outcome': outcome},
        ).toString(),
      ),
    );
    _expectProviderError(
      response,
      caseId: 'callback-provider.$outcome',
      error: outcome == 'failure' ? 'auth_error' : 'callback_error',
      statusCode: outcome == 'failure' ? 401 : 400,
    );
  }
}

Future<_OidcStart> _startOidc(
  AuthRuntimeConformanceSend send, {
  String? callbackUrl,
}) async {
  final queryParameters = <String, String>{};
  if (callbackUrl != null) queryParameters['callbackUrl'] = callbackUrl;
  final response = await send(
    AuthRuntimeConformanceRequest(
      method: 'GET',
      path: Uri(
        path: '/auth/signin/$authExternalProviderRuntimeOidcProviderId',
        queryParameters: queryParameters,
      ).toString(),
    ),
  );
  _expectStatus(response, 302, 'oidc.start');
  final location = _location(response);
  final uri = location == null ? null : Uri.tryParse(location);
  final state = uri?.queryParameters['state'];
  final nonce = uri?.queryParameters['nonce'];
  final challenge = uri?.queryParameters['code_challenge'];
  _check(
    uri?.host == 'provider.runtime.test' &&
        state != null &&
        state.isNotEmpty &&
        nonce != null &&
        nonce.isNotEmpty &&
        challenge != null &&
        challenge.isNotEmpty &&
        uri?.queryParameters['code_challenge_method'] == 'S256',
    'oidc.start',
    'OIDC start omitted state, S256 PKCE, nonce, or provider origin.',
  );
  final cookieHeader = _responseCookieHeader(response);
  _check(
    cookieHeader.split(';').length >= 2,
    'oidc.start',
    'OIDC start did not bind state to both browser and host session cookies.',
  );
  return _OidcStart(
    state: state!,
    nonce: nonce!,
    challenge: challenge!,
    cookieHeader: cookieHeader,
  );
}

Future<AuthRuntimeConformanceResponse> _finishOidc(
  AuthRuntimeConformanceSend send, {
  required _OidcStart start,
  required String cookie,
  required String state,
  required String variant,
}) {
  return send(
    AuthRuntimeConformanceRequest(
      method: 'GET',
      path: Uri(
        path: '/auth/callback/$authExternalProviderRuntimeOidcProviderId',
        queryParameters: <String, String>{
          'code': _authorizationCode(
            nonce: start.nonce,
            challenge: start.challenge,
            variant: variant,
          ),
          'state': state,
        },
      ).toString(),
      headers: <String, List<String>>{
        'cookie': <String>[cookie],
      },
    ),
  );
}

OAuthProvider<Map<String, dynamic>> _createOidcProvider() =>
    OAuthProvider<Map<String, dynamic>>(
      id: authExternalProviderRuntimeOidcProviderId,
      name: 'Runtime OIDC',
      type: AuthProviderType.oidc,
      clientId: _oidcClientId,
      clientSecret: 'runtime-provider-client-secret',
      authorizationEndpoint: Uri.parse('$_oidcIssuer/authorize'),
      tokenEndpoint: Uri.parse('$_oidcIssuer/token'),
      redirectUri:
          'https://runtime.example/auth/callback/'
          '$authExternalProviderRuntimeOidcProviderId',
      oidcIssuer: Uri.parse(_oidcIssuer),
      oidcJwksUri: Uri.parse('$_oidcIssuer/jwks'),
      oidcAlgorithms: const <String>['HS256'],
      scopes: const <String>['openid', 'profile', 'email'],
      profile: (profile) => AuthUser(
        id: profile['sub']?.toString() ?? '',
        email: profile['email']?.toString(),
        name: profile['name']?.toString(),
      ),
    );

AuthTestHttpClient _createProviderClient() => AuthTestHttpClient(
  fallback: (request) {
    if (request.uri.path == '/jwks') {
      return AuthTestHttpResponse.json(<String, Object?>{
        'keys': <Map<String, dynamic>>[_oidcJwk()],
      });
    }
    if (request.uri.path != '/token') {
      return const AuthTestHttpResponse(
        statusCode: 500,
        body: authExternalProviderRuntimeFailureMarker,
      );
    }

    final fields = Uri.splitQueryString(request.body);
    final code = fields['code'];
    if (code == 'provider-failure') {
      return const AuthTestHttpResponse(
        statusCode: 502,
        body: authExternalProviderRuntimeFailureMarker,
      );
    }
    final payload = _decodeAuthorizationCode(code);
    final verifier = fields['code_verifier'];
    if (payload == null ||
        verifier == null ||
        pkceS256CodeChallenge(verifier) != payload.challenge) {
      return const AuthTestHttpResponse(
        statusCode: 400,
        body: authExternalProviderRuntimeFailureMarker,
      );
    }

    return AuthTestHttpResponse.json(<String, Object?>{
      'access_token': 'runtime-access-${payload.variant}',
      'token_type': 'Bearer',
      'expires_in': 3600,
      'id_token': _signedOidcToken(
        nonce: payload.variant == 'bad-nonce'
            ? 'tampered-provider-nonce'
            : payload.nonce,
        subject: 'runtime-${payload.variant}',
        emailVerified: payload.variant != 'unverified',
      ),
    });
  },
);

Map<String, dynamic> _oidcJwk() => <String, dynamic>{
  'kty': 'oct',
  'kid': 'runtime-oidc-key',
  'alg': 'HS256',
  'k': base64Url.encode(utf8.encode(_oidcSecret)).replaceAll('=', ''),
};

String _signedOidcToken({
  required String nonce,
  required String subject,
  required bool emailVerified,
}) {
  final builder = JsonWebSignatureBuilder()
    ..jsonContent = <String, dynamic>{
      'sub': subject,
      'email': _email,
      'email_verified': emailVerified,
      'name': 'Runtime Provider User',
      'iss': _oidcIssuer,
      'aud': <String>[_oidcClientId],
      'exp': 4102444800,
      'nonce': nonce,
    }
    ..setProtectedHeader('alg', 'HS256')
    ..setProtectedHeader('kid', 'runtime-oidc-key')
    ..addRecipient(JsonWebKey.fromJson(_oidcJwk()), algorithm: 'HS256');
  return builder.build().toCompactSerialization();
}

String _authorizationCode({
  required String nonce,
  required String challenge,
  required String variant,
}) => base64Url
    .encode(
      utf8.encode(
        jsonEncode(<String, String>{
          'nonce': nonce,
          'challenge': challenge,
          'variant': variant,
        }),
      ),
    )
    .replaceAll('=', '');

_AuthorizationCode? _decodeAuthorizationCode(String? code) {
  if (code == null || code.length > 4096) return null;
  try {
    final decoded = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(code))),
    );
    if (decoded is! Map) return null;
    final nonce = decoded['nonce'];
    final challenge = decoded['challenge'];
    final variant = decoded['variant'];
    if (nonce is! String ||
        nonce.isEmpty ||
        challenge is! String ||
        challenge.isEmpty ||
        variant is! String ||
        !const <String>{
          'verified',
          'unverified',
          'bad-nonce',
          'unsafe',
        }.contains(variant)) {
      return null;
    }
    return _AuthorizationCode(
      nonce: nonce,
      challenge: challenge,
      variant: variant,
    );
  } catch (_) {
    return null;
  }
}

final class _RuntimeCallbackProvider extends AuthProvider
    with CallbackProvider {
  _RuntimeCallbackProvider()
    : super(
        id: authExternalProviderRuntimeCallbackProviderId,
        name: 'Runtime callback',
        type: AuthProviderType.oauth,
      );

  @override
  CallbackResult handleCallback(
    AuthContext context,
    Map<String, String> params,
  ) => switch (params['outcome']) {
    'failure' => const CallbackResult.failure(
      authExternalProviderRuntimeFailureMarker,
    ),
    'throw' => throw StateError(authExternalProviderRuntimeFailureMarker),
    _ => CallbackResult.success(
      AuthUser(
        id: 'runtime-custom-user',
        email: 'custom-runtime@example.test',
        name: 'Runtime Custom User',
      ),
      redirect: params['redirect'],
    ),
  };
}

void _expectProviderError(
  AuthRuntimeConformanceResponse response, {
  required String caseId,
  required String error,
  int statusCode = 401,
}) {
  _expectStatus(response, statusCode, caseId);
  final body = _jsonObject(response, caseId);
  _check(
    body['error'] == error,
    caseId,
    'Expected error "$error", received "${body['error']}".',
  );
  _check(
    !response.body.contains(authExternalProviderRuntimeFailureMarker),
    caseId,
    'Provider diagnostics leaked into the public error response.',
  );
}

void _expectStrategyAndCookie(
  AuthRuntimeConformanceResponse response,
  Map<String, Object?> body, {
  required String caseId,
  required bool expectJwt,
}) {
  _check(
    body['strategy'] == (expectJwt ? 'jwt' : 'session'),
    caseId,
    'The host did not issue the expected authentication strategy.',
  );
  _expectIssuedAuthCookie(response, caseId: caseId, expectJwt: expectJwt);
}

void _expectIssuedAuthCookie(
  AuthRuntimeConformanceResponse response, {
  required String caseId,
  required bool expectJwt,
}) {
  final name = expectJwt
      ? _jwtCookieName
      : authExternalProviderRuntimeCookieName;
  _check(
    response
        .headerValues('set-cookie')
        .any((value) => value.trimLeft().startsWith('$name=')),
    caseId,
    'The host did not issue the expected $name cookie.',
  );
}

Map<String, List<String>> _jsonHeaders({required String origin}) =>
    <String, List<String>>{
      'content-type': const <String>['application/json'],
      'origin': <String>[origin],
      'sec-fetch-site': const <String>['same-origin'],
    };

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

Object? _userField(Map<String, Object?> body, String field) {
  final user = body['user'];
  return user is Map<String, Object?> ? user[field] : null;
}

void _expectStatus(
  AuthRuntimeConformanceResponse response,
  int statusCode,
  String caseId,
) {
  _check(
    response.statusCode == statusCode,
    caseId,
    'Expected status $statusCode, received ${response.statusCode}: '
    '${response.body}',
  );
}

String? _location(AuthRuntimeConformanceResponse response) {
  final values = response.headerValues('location');
  return values.isEmpty ? null : values.first;
}

String _responseCookieHeader(AuthRuntimeConformanceResponse response) =>
    response
        .headerValues('set-cookie')
        .map((value) => value.split(';').first.trim())
        .where((value) => value.contains('='))
        .join('; ');

String? _cookieNamed(String cookieHeader, String name) {
  final prefix = '$name=';
  for (final pair in cookieHeader.split(';')) {
    final candidate = pair.trim();
    if (candidate.startsWith(prefix)) return candidate;
  }
  return null;
}

void _check(bool condition, String caseId, String message) {
  if (!condition) {
    throw AuthRuntimeConformanceFailure(caseId: caseId, message: message);
  }
}

final class _AuthorizationCode {
  const _AuthorizationCode({
    required this.nonce,
    required this.challenge,
    required this.variant,
  });

  final String nonce;
  final String challenge;
  final String variant;
}

final class _OidcStart {
  const _OidcStart({
    required this.state,
    required this.nonce,
    required this.challenge,
    required this.cookieHeader,
  });

  final String state;
  final String nonce;
  final String challenge;
  final String cookieHeader;
}

final class _ConformancePasswordHasher implements PasswordHasher {
  const _ConformancePasswordHasher();

  @override
  String hash(String password) => 'runtime-hash:$password';

  @override
  PasswordVerification verify(String password, String encodedHash) =>
      PasswordVerification(
        matches: encodedHash == 'runtime-hash:$password',
        needsRehash: false,
      );
}
