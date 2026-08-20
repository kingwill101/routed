import 'dart:convert';
import 'dart:io' show SameSite;

import 'package:routed_core/routed_core.dart';
import 'package:routed_sessions/routed_sessions.dart';

import '../../routed_auth.dart';
import 'runtime_auth_conformance.dart';

/// Session cookie used by [createAuthPluginRuntimeConformanceEngine].
const authPluginRuntimeConformanceCookieName = 'runtime_plugin_auth_session';

/// Email used by the email-OTP conformance flow.
const authPluginRuntimeConformanceOtpEmail = 'otp-runtime@example.test';

/// One-time code delivered by the email-OTP conformance fixture.
const authPluginRuntimeConformanceOtpCode = '482913';

/// Username registered by the plugin conformance flow.
const authPluginRuntimeConformanceUsername = 'runtime.user';

/// Email registered by the username conformance flow.
const authPluginRuntimeConformanceUsernameEmail =
    'username-runtime@example.test';

/// Password accepted by the username conformance fixture.
const authPluginRuntimeConformancePassword = 'runtime-plugin-password-123';

/// Creates an engine containing deterministic, provider-free auth plugins.
///
/// The fixture is intended for host-adapter integration tests. It does not
/// contact an email service, WebAuthn metadata service, or any other external
/// provider. Set [includeTwoFactor] to `false` to verify that two-factor routes
/// are absent when the plugin is not installed.
Engine createAuthPluginRuntimeConformanceEngine({
  bool includeTwoFactor = true,
}) {
  final store = InMemoryAuthStore();
  final webAuthnProvider = WebAuthnProvider(
    getUserInfo: (_, _, _) => null,
    getRelyingParty: (_, _) => const WebAuthnRelyingParty(
      id: 'runtime.example',
      name: 'Routed runtime conformance',
      origin: 'https://runtime.example',
    ),
  );
  final plugins = <AuthServerPlugin<EngineContext>>[
    EmailOtpPlugin<EngineContext>(
      rateLimitHashKey: 'runtime-email-otp-rate-limit-key',
      generateOtp: (_) => authPluginRuntimeConformanceOtpCode,
      sendCode: (_) {},
    ),
    UsernamePlugin<EngineContext>(),
    AuthApiKeyPlugin<EngineContext>(
      store: InMemoryAuthApiKeyStore(),
      sessionExchangeEnabled: true,
      keyIdGenerator: ({int length = 32}) => 'runtime-key-id',
      secretGenerator: ({int length = 32}) => 'runtime-key-secret',
    ),
    WebAuthnPlugin<EngineContext>(provider: webAuthnProvider),
    AnonymousPlugin<EngineContext>(),
    if (includeTwoFactor)
      TwoFactorPlugin<EngineContext>(
        store: InMemoryAuthTwoFactorStore(),
        challengeStore: InMemoryAuthTwoFactorChallengeStore(),
        trustedDeviceStore: InMemoryAuthTwoFactorTrustedDeviceStore(),
        stepUpStore: InMemoryAuthTwoFactorStepUpStore(),
        secretProtector: const PlaintextAuthTwoFactorSecretProtector(),
        secretGenerator: (length) =>
            List<int>.generate(length, (index) => (index + 1) & 0xff),
      ),
  ];
  final manager = AuthManager(
    AuthOptions<EngineContext>(
      store: store,
      storeMode: AuthStoreMode.ephemeral,
      providers: <AuthProvider>[webAuthnProvider],
      plugins: plugins,
      passwordHasher: const _ConformancePasswordHasher(),
      sessionStrategy: AuthSessionStrategy.session,
      enforceCsrf: true,
      cookiePolicy: AuthCookiePolicy.development,
    ),
  );
  final sessionKey = base64.encode(
    List<int>.generate(32, (index) => 255 - index),
  );
  final sessionConfig = SessionConfig.cookie(
    appKey: 'base64:$sessionKey',
    cookieName: authPluginRuntimeConformanceCookieName,
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

/// Verifies representative plugin flows through an arbitrary host transport.
///
/// [send] must target an engine created with the default plugin topology.
/// [sendWithoutTwoFactor] must target a fixture created with
/// `includeTwoFactor: false`; it is used only to confirm opt-in route gating.
/// This helper intentionally has no dependency on `package:test` or browser
/// interop libraries.
Future<void> verifyAuthPluginRuntimeConformance({
  required Uri origin,
  required AuthRuntimeConformanceSend send,
  required AuthRuntimeConformanceSend sendWithoutTwoFactor,
}) async {
  final originHeader = origin.toString();

  await _verifyEmailOtp(send, originHeader);
  final usernameSession = await _verifyUsername(send, originHeader);
  final csrf = await _issueCsrf(send, cookie: usernameSession);
  await _verifyApiKeyExchange(
    send,
    originHeader: originHeader,
    sessionCookie: csrf.cookie,
    csrf: csrf.token,
  );
  await _verifyWebAuthnBoundary(
    send,
    originHeader: originHeader,
    sessionCookie: csrf.cookie,
    csrf: csrf.token,
  );
  await _verifyAnonymous(send, originHeader);
  await _verifyTwoFactorGating(send, sendWithoutTwoFactor);
}

Future<void> _verifyEmailOtp(
  AuthRuntimeConformanceSend send,
  String origin,
) async {
  final sent = await send(
    AuthRuntimeConformanceRequest(
      method: 'POST',
      path: '/auth/email-otp/send-verification-otp',
      headers: _jsonHeaders(),
      body: jsonEncode(<String, Object?>{
        'email': authPluginRuntimeConformanceOtpEmail,
        'type': 'sign-in',
      }),
    ),
  );
  _expectStatus(sent, 200, 'email-otp.send');
  _check(
    sent.body.contains(authPluginRuntimeConformanceOtpCode) == false,
    'email-otp.send',
    'The delivered OTP leaked into the HTTP response.',
  );

  final signedIn = await send(
    AuthRuntimeConformanceRequest(
      method: 'POST',
      path: '/auth/sign-in/email-otp',
      headers: _jsonHeaders(origin: origin),
      body: jsonEncode(<String, Object?>{
        'email': authPluginRuntimeConformanceOtpEmail,
        'otp': authPluginRuntimeConformanceOtpCode,
      }),
    ),
  );
  _expectStatus(signedIn, 200, 'email-otp.sign-in');
  final body = _jsonObject(signedIn, 'email-otp.sign-in');
  _check(
    _userField(body, 'email') == authPluginRuntimeConformanceOtpEmail,
    'email-otp.sign-in',
    'The OTP sign-in response did not contain the expected user.',
  );
  _requireSessionCookie(signedIn, 'email-otp.sign-in');
}

Future<String> _verifyUsername(
  AuthRuntimeConformanceSend send,
  String origin,
) async {
  final registered = await send(
    AuthRuntimeConformanceRequest(
      method: 'POST',
      path: '/auth/username/register',
      headers: _jsonHeaders(origin: origin),
      body: jsonEncode(<String, Object?>{
        'username': ' Runtime.User ',
        'email': authPluginRuntimeConformanceUsernameEmail.toUpperCase(),
        'password': authPluginRuntimeConformancePassword,
      }),
    ),
  );
  _expectStatus(registered, 200, 'username.register');
  final registeredBody = _jsonObject(registered, 'username.register');
  _check(
    registeredBody['username'] == authPluginRuntimeConformanceUsername,
    'username.register',
    'The username was not normalized by the plugin.',
  );
  _check(
    registered.body.contains(authPluginRuntimeConformancePassword) == false,
    'username.register',
    'The username password leaked into the HTTP response.',
  );

  final signedIn = await send(
    AuthRuntimeConformanceRequest(
      method: 'POST',
      path: '/auth/username/sign-in',
      headers: _jsonHeaders(origin: origin),
      body: jsonEncode(<String, Object?>{
        'identifier': authPluginRuntimeConformanceUsernameEmail.toUpperCase(),
        'password': authPluginRuntimeConformancePassword,
      }),
    ),
  );
  _expectStatus(signedIn, 200, 'username.sign-in');
  final signedInBody = _jsonObject(signedIn, 'username.sign-in');
  _check(
    _userField(signedInBody, 'email') ==
        authPluginRuntimeConformanceUsernameEmail,
    'username.sign-in',
    'The username sign-in response did not contain the expected user.',
  );
  return _requireSessionCookie(signedIn, 'username.sign-in');
}

Future<void> _verifyApiKeyExchange(
  AuthRuntimeConformanceSend send, {
  required String originHeader,
  required String sessionCookie,
  required String csrf,
}) async {
  final created = await send(
    AuthRuntimeConformanceRequest(
      method: 'POST',
      path: '/auth/api-keys/create',
      headers: _jsonHeaders(cookie: sessionCookie, origin: originHeader),
      body: jsonEncode(<String, Object?>{
        'name': 'runtime worker',
        'scopes': <String>['jobs:read'],
        '_csrf': csrf,
      }),
    ),
  );
  _expectStatus(created, 200, 'api-key.create');
  final createdBody = _jsonObject(created, 'api-key.create');
  final rawKey = createdBody['apiKey'];
  _check(
    rawKey is String && rawKey.startsWith('rka.'),
    'api-key.create',
    'The API-key response did not contain the one-time raw key.',
  );

  final listed = await send(
    AuthRuntimeConformanceRequest(
      method: 'GET',
      path: '/auth/api-keys/list',
      headers: <String, List<String>>{
        'cookie': <String>[sessionCookie],
      },
    ),
  );
  _expectStatus(listed, 200, 'api-key.list');
  _check(
    listed.body.contains(rawKey as String) == false,
    'api-key.list',
    'The one-time raw API key appeared in the list response.',
  );

  final exchanged = await send(
    AuthRuntimeConformanceRequest(
      method: 'POST',
      path: '/auth/api-keys/exchange',
      headers: _jsonHeaders(apiKey: rawKey),
      body: '{}',
    ),
  );
  _expectStatus(exchanged, 200, 'api-key.exchange');
  final exchangedBody = _jsonObject(exchanged, 'api-key.exchange');
  _check(
    _userField(exchangedBody, 'email') ==
        authPluginRuntimeConformanceUsernameEmail,
    'api-key.exchange',
    'API-key exchange did not authenticate the owning user.',
  );
  _requireSessionCookie(exchanged, 'api-key.exchange');
}

Future<void> _verifyWebAuthnBoundary(
  AuthRuntimeConformanceSend send, {
  required String originHeader,
  required String sessionCookie,
  required String csrf,
}) async {
  final registrationOptions = await send(
    AuthRuntimeConformanceRequest(
      method: 'POST',
      path: '/auth/webauthn/register/options',
      headers: _jsonHeaders(cookie: sessionCookie, origin: originHeader),
      body: jsonEncode(<String, Object?>{'_csrf': csrf}),
    ),
  );
  _expectStatus(registrationOptions, 200, 'webauthn.registration-options');
  final registrationBody = _jsonObject(
    registrationOptions,
    'webauthn.registration-options',
  );
  _check(
    registrationBody['challenge'] is String &&
        (registrationBody['challenge'] as String).isNotEmpty,
    'webauthn.registration-options',
    'WebAuthn registration options did not contain a challenge.',
  );

  final authenticationOptions = await send(
    AuthRuntimeConformanceRequest(
      method: 'POST',
      path: '/auth/webauthn/authenticate/options',
      headers: _jsonHeaders(),
      body: '{}',
    ),
  );
  _expectStatus(authenticationOptions, 200, 'webauthn.authentication-options');
  final authenticationBody = _jsonObject(
    authenticationOptions,
    'webauthn.authentication-options',
  );
  _check(
    authenticationBody['challenge'] is String &&
        (authenticationBody['challenge'] as String).isNotEmpty,
    'webauthn.authentication-options',
    'WebAuthn authentication options did not contain a challenge.',
  );

  final malformed = await send(
    AuthRuntimeConformanceRequest(
      method: 'POST',
      path: '/auth/webauthn/authenticate/verify',
      headers: _jsonHeaders(),
      body: jsonEncode(<String, Object?>{'credential': <String, Object?>{}}),
    ),
  );
  _expectStatus(malformed, 401, 'webauthn.error-boundary');
  final malformedBody = _jsonObject(malformed, 'webauthn.error-boundary');
  final error = malformedBody['error'];
  _check(
    error is String && error.startsWith('webauthn_'),
    'webauthn.error-boundary',
    'Malformed WebAuthn input did not return a sanitized WebAuthn error.',
  );
  _check(
    malformed.body.contains('StateError') == false &&
        malformed.body.contains('/src/') == false,
    'webauthn.error-boundary',
    'The WebAuthn error response leaked internal implementation details.',
  );
}

Future<void> _verifyAnonymous(
  AuthRuntimeConformanceSend send,
  String origin,
) async {
  final rejected = await send(
    AuthRuntimeConformanceRequest(
      method: 'POST',
      path: '/auth/sign-in/anonymous',
      headers: _jsonHeaders(origin: 'https://attacker.example'),
      body: '{}',
    ),
  );
  _expectError(
    rejected,
    caseId: 'anonymous.cross-origin',
    statusCode: 403,
    error: 'invalid_origin',
  );

  final signedIn = await send(
    AuthRuntimeConformanceRequest(
      method: 'POST',
      path: '/auth/sign-in/anonymous',
      headers: _jsonHeaders(origin: origin),
      body: '{}',
    ),
  );
  _expectStatus(signedIn, 200, 'anonymous.sign-in');
  final body = _jsonObject(signedIn, 'anonymous.sign-in');
  _check(
    _userField(body, 'isAnonymous') == true,
    'anonymous.sign-in',
    'Anonymous sign-in did not return an anonymous user.',
  );
  _requireSessionCookie(signedIn, 'anonymous.sign-in');
}

Future<void> _verifyTwoFactorGating(
  AuthRuntimeConformanceSend send,
  AuthRuntimeConformanceSend sendWithoutTwoFactor,
) async {
  final installed = await send(
    const AuthRuntimeConformanceRequest(
      method: 'GET',
      path: '/auth/2fa/status',
    ),
  );
  _expectError(
    installed,
    caseId: 'two-factor.installed',
    statusCode: 401,
    error: 'unauthorized',
  );

  final absent = await sendWithoutTwoFactor(
    const AuthRuntimeConformanceRequest(
      method: 'GET',
      path: '/auth/2fa/status',
    ),
  );
  _expectStatus(absent, 404, 'two-factor.absent');
  _check(
    absent.body.contains('two_factor_unavailable') == false,
    'two-factor.absent',
    'An uninstalled two-factor plugin exposed an auth route.',
  );
}

Future<_CsrfState> _issueCsrf(
  AuthRuntimeConformanceSend send, {
  required String cookie,
}) async {
  final response = await send(
    AuthRuntimeConformanceRequest(
      method: 'GET',
      path: '/auth/csrf',
      headers: <String, List<String>>{
        'cookie': <String>[cookie],
      },
    ),
  );
  _expectStatus(response, 200, 'plugin.csrf');
  final token = _jsonObject(response, 'plugin.csrf')['csrfToken'];
  _check(
    token is String && token.isNotEmpty,
    'plugin.csrf',
    'Expected a non-empty CSRF token.',
  );
  return _CsrfState(
    token: token as String,
    cookie: _optionalSessionCookie(response) ?? cookie,
  );
}

Map<String, List<String>> _jsonHeaders({
  String? cookie,
  String? origin,
  String? apiKey,
}) => <String, List<String>>{
  'content-type': const <String>['application/json'],
  if (cookie != null) 'cookie': <String>[cookie],
  if (origin != null) ...<String, List<String>>{
    'origin': <String>[origin],
    'sec-fetch-site': const <String>['same-origin'],
  },
  if (apiKey != null) 'x-api-key': <String>[apiKey],
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
  return value as Map<String, Object?>;
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

void _expectError(
  AuthRuntimeConformanceResponse response, {
  required String caseId,
  required int statusCode,
  required String error,
}) {
  _expectStatus(response, statusCode, caseId);
  final body = _jsonObject(response, caseId);
  _check(
    body['error'] == error,
    caseId,
    'Expected error "$error", received "${body['error']}".',
  );
}

String _requireSessionCookie(
  AuthRuntimeConformanceResponse response,
  String caseId,
) {
  final cookie = _optionalSessionCookie(response);
  if (cookie != null) return cookie;
  throw AuthRuntimeConformanceFailure(
    caseId: caseId,
    message: 'Expected a $authPluginRuntimeConformanceCookieName cookie.',
  );
}

String? _optionalSessionCookie(AuthRuntimeConformanceResponse response) {
  final prefix = '$authPluginRuntimeConformanceCookieName=';
  for (final value in response.headerValues('set-cookie')) {
    final candidate = value.trimLeft();
    if (candidate.startsWith(prefix)) return candidate.split(';').first;
  }
  return null;
}

void _check(bool condition, String caseId, String message) {
  if (!condition) {
    throw AuthRuntimeConformanceFailure(caseId: caseId, message: message);
  }
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

final class _CsrfState {
  const _CsrfState({required this.token, required this.cookie});

  final String token;
  final String cookie;
}
