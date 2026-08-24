import 'dart:convert';
import 'dart:io' show SameSite;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:routed_core/routed_core.dart';
import 'package:routed_sessions/routed_sessions.dart';

import '../../routed_auth.dart';
import 'runtime_auth_conformance.dart';
import 'webauthn_runtime_auth_conformance.dart';

/// Session cookie used by [createAuthPluginRuntimeConformanceEngine].
const authPluginRuntimeConformanceCookieName = 'runtime_plugin_auth_session';

/// Email used by the email-OTP conformance flow.
const authPluginRuntimeConformanceOtpEmail = 'otp-runtime@example.test';

/// One-time code delivered by the email-OTP conformance fixture.
const authPluginRuntimeConformanceOtpCode = '482913';

/// Provider ID resolved through the typed magic-link route placeholder.
const authPluginRuntimeConformanceMagicLinkProviderId = 'runtime-email';

/// Email used by the magic-link client/runtime conformance flow.
const authPluginRuntimeConformanceMagicLinkEmail =
    'magic-link-runtime@example.test';

/// One-time raw token delivered only to the magic-link fixture sender.
const _authPluginRuntimeConformanceMagicLinkToken =
    'runtime-magic-link-token-7f8c2b';

/// Canonical number used by the phone-number client/runtime conformance flow.
const authPluginRuntimeConformancePhoneNumber = '+18765550101';

/// One-time raw code exposed only to the phone delivery fixture.
const _authPluginRuntimeConformancePhoneCode = '739251';

const _authPluginRuntimePhoneDeliveryFailureNumber = '+18765550102';
const _authPluginRuntimePhoneDeliveryFailureMarker =
    '/srv/secrets/runtime-sms-provider.key';

/// A copy of one provider-owned phone-code delivery.
final class AuthPluginRuntimePhoneDelivery {
  const AuthPluginRuntimePhoneDelivery({
    required this.phoneNumber,
    required this.code,
    required this.expiresAt,
  });

  final String phoneNumber;
  final String code;
  final DateTime expiresAt;
}

/// Records the provider boundary used by the cross-host phone flow.
///
/// A recorder belongs to one engine fixture. This keeps raw test codes scoped
/// to the host test that owns them and avoids shared mutable state when several
/// runtime matrices execute concurrently.
final class AuthPluginRuntimePhoneDeliveryRecorder {
  final List<AuthPluginRuntimePhoneDelivery> _deliveries =
      <AuthPluginRuntimePhoneDelivery>[];

  List<AuthPluginRuntimePhoneDelivery> get deliveries =>
      List<AuthPluginRuntimePhoneDelivery>.unmodifiable(_deliveries);

  Iterable<AuthPluginRuntimePhoneDelivery> forPhone(String phoneNumber) =>
      _deliveries.where((delivery) => delivery.phoneNumber == phoneNumber);

  void _record(AuthPhoneNumberCodeDelivery<EngineContext> delivery) {
    _deliveries.add(
      AuthPluginRuntimePhoneDelivery(
        phoneNumber: delivery.phoneNumber,
        code: delivery.code,
        expiresAt: delivery.expiresAt,
      ),
    );
    if (delivery.phoneNumber == _authPluginRuntimePhoneDeliveryFailureNumber) {
      throw StateError(
        '$_authPluginRuntimePhoneDeliveryFailureMarker raw=${delivery.code}',
      );
    }
  }
}

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
  AuthPluginRuntimePhoneDeliveryRecorder? phoneDeliveryRecorder,
}) {
  final store = InMemoryAuthStore();
  final phoneDeliveries =
      phoneDeliveryRecorder ?? AuthPluginRuntimePhoneDeliveryRecorder();
  final webAuthnProvider = WebAuthnProvider(
    getUserInfo: (_, _, _) => null,
    getRelyingParty: (_, _) => const WebAuthnRelyingParty(
      id: 'runtime.example',
      name: 'Routed runtime conformance',
      origin: 'https://runtime.example',
    ),
  );
  final plugins = <AuthServerPlugin<EngineContext>>[
    MagicLinkPlugin<EngineContext>(
      id: authPluginRuntimeConformanceMagicLinkProviderId,
      tokenGenerator: () => _authPluginRuntimeConformanceMagicLinkToken,
      sendMagicLink: (_) {},
    ),
    PhoneNumberPlugin<EngineContext>(
      sendCode: phoneDeliveries._record,
      codeHashKey: 'runtime-phone-code-hash-key-32-bytes',
      allowSignUp: true,
      allowedAttempts: 3,
      generateCode: (_) => _authPluginRuntimeConformancePhoneCode,
    ),
    EmailOtpPlugin<EngineContext>(
      secret: 'runtime-email-otp-rate-limit-key',
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
        backend: InMemoryAuthTwoFactorBackend(),
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
  required AuthPluginRuntimePhoneDeliveryRecorder phoneDeliveryRecorder,
}) async {
  final originHeader = origin.toString();

  await _verifyMagicLink(send, origin);
  await _verifyPhoneNumber(send, origin, phoneDeliveryRecorder);
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
  await verifyAuthWebAuthnBrowserRuntimeConformance(
    transportOrigin: origin,
    send: send,
    sessionCookie: csrf.cookie,
    sessionCookieName: authPluginRuntimeConformanceCookieName,
    csrfToken: csrf.token,
    expectedUserEmail: authPluginRuntimeConformanceUsernameEmail,
  );
  await _verifyAnonymous(send, originHeader);
  await _verifyTwoFactorGating(send, sendWithoutTwoFactor);
}

/// Verifies only the browser-shaped WebAuthn/passkey plugin flow.
///
/// The [send] target must be an engine created by
/// [createAuthPluginRuntimeConformanceEngine]. The helper first establishes a
/// deterministic username-backed user and then runs registration,
/// authentication, challenge-replay, counter-replay, and error-sanitization
/// checks using browser-shaped ASN.1 DER ES256 assertions.
Future<void> verifyAuthWebAuthnPluginRuntimeConformance({
  required Uri origin,
  required AuthRuntimeConformanceSend send,
}) async {
  final session = await _verifyUsername(send, origin.toString());
  final csrf = await _issueCsrf(send, cookie: session);
  await verifyAuthWebAuthnBrowserRuntimeConformance(
    transportOrigin: origin,
    send: send,
    sessionCookie: csrf.cookie,
    sessionCookieName: authPluginRuntimeConformanceCookieName,
    csrfToken: csrf.token,
    expectedUserEmail: authPluginRuntimeConformanceUsernameEmail,
  );
}

Future<void> _verifyMagicLink(
  AuthRuntimeConformanceSend send,
  Uri origin,
) async {
  const magicLinkPlugin = AuthMagicLinkClientPlugin(
    provider: authPluginRuntimeConformanceMagicLinkProviderId,
  );
  const providerPlugin = AuthProviderClientPlugin();
  const sessionPlugin = AuthSessionClientPlugin();
  final transport = _AuthRuntimeConformanceHttpClient(send);
  final client = AuthClient(
    baseUrl: origin,
    httpClient: transport,
    headers: <String, String>{
      'origin': origin.toString(),
      'sec-fetch-site': 'same-origin',
    },
    plugins: const <AuthClientPlugin<dynamic>>[
      magicLinkPlugin,
      providerPlugin,
      sessionPlugin,
    ],
  );
  final magicLink = client.plugins.use(magicLinkPlugin);
  final providers = await _clientOperation(
    () => client.plugins.use(providerPlugin).list(),
    caseId: 'magic-link.server-plugin',
  );
  _check(
    providers.any(
      (provider) =>
          provider.id == authPluginRuntimeConformanceMagicLinkProviderId &&
          provider.type == AuthProviderType.email.name,
    ),
    'magic-link.server-plugin',
    'The installed server plugin was absent from provider metadata.',
  );

  final sent = await magicLink.send(
    email: authPluginRuntimeConformanceMagicLinkEmail,
  );
  _check(
    sent.email == authPluginRuntimeConformanceMagicLinkEmail,
    'magic-link.send',
    'The typed client did not preserve the requested email.',
  );
  _check(
    transport.requestPaths.contains(
      '/auth/signin/$authPluginRuntimeConformanceMagicLinkProviderId',
    ),
    'magic-link.send.path',
    'The typed {provider} sign-in route did not resolve to the plugin ID.',
  );
  _check(
    transport.responses.every(
      (response) =>
          !response.body.contains(_authPluginRuntimeConformanceMagicLinkToken),
    ),
    'magic-link.send.secret',
    'The raw magic-link token leaked into an HTTP response.',
  );

  final otherBrowserTransport = _AuthRuntimeConformanceHttpClient(send);
  final otherBrowserClient = AuthClient(
    baseUrl: origin,
    httpClient: otherBrowserTransport,
    headers: <String, String>{
      'origin': origin.toString(),
      'sec-fetch-site': 'same-origin',
    },
    plugins: const <AuthClientPlugin<dynamic>>[magicLinkPlugin],
  );
  await _expectMagicLinkClientError(
    () => otherBrowserClient.plugins
        .use(magicLinkPlugin)
        .verify(
          email: authPluginRuntimeConformanceMagicLinkEmail,
          token: _authPluginRuntimeConformanceMagicLinkToken,
        ),
    caseId: 'magic-link.browser-binding',
    statusCode: 401,
    error: 'invalid_token',
  );

  final cookieHeader = await _authClientCookieHeader(client.cookieStore);
  for (final token in _hostileMagicLinkTokens()) {
    final response = await send(
      AuthRuntimeConformanceRequest(
        method: 'GET',
        path: _magicLinkCallbackPath(token),
        headers: <String, List<String>>{
          'cookie': <String>[cookieHeader],
        },
      ),
    );
    _expectError(
      response,
      caseId: 'magic-link.hostile-token',
      statusCode: 401,
      error: 'invalid_token',
    );
    _check(
      !response.body.contains(token) &&
          !response.body.contains('StateError') &&
          !response.body.contains('/src/'),
      'magic-link.hostile-token',
      'A hostile token reached the public error response.',
    );
  }

  final result = await magicLink.verify(
    email: authPluginRuntimeConformanceMagicLinkEmail,
    token: _authPluginRuntimeConformanceMagicLinkToken,
  );
  _check(
    result.redirectUrl == null &&
        result.session?.user.email ==
            authPluginRuntimeConformanceMagicLinkEmail,
    'magic-link.verify',
    'The typed callback client did not return the authenticated session.',
  );
  _check(
    transport.requestPaths.contains(
      '/auth/callback/$authPluginRuntimeConformanceMagicLinkProviderId',
    ),
    'magic-link.verify.path',
    'The typed {provider} callback route did not resolve to the plugin ID.',
  );
  final current = await client.plugins.use(sessionPlugin).current();
  _check(
    current?.user.email == authPluginRuntimeConformanceMagicLinkEmail,
    'magic-link.session',
    'The host-owned session was not readable through the installed client.',
  );
  await _expectMagicLinkClientError(
    () => magicLink.verify(
      email: authPluginRuntimeConformanceMagicLinkEmail,
      token: _authPluginRuntimeConformanceMagicLinkToken,
    ),
    caseId: 'magic-link.replay',
    statusCode: 401,
    error: 'invalid_token',
  );

  await magicLink.send(email: authPluginRuntimeConformanceMagicLinkEmail);
  final concurrentCookie = await _authClientCookieHeader(client.cookieStore);
  final concurrent = await Future.wait(
    List<Future<AuthRuntimeConformanceResponse>>.generate(
      8,
      (_) => send(
        AuthRuntimeConformanceRequest(
          method: 'GET',
          path: _magicLinkCallbackPath(
            _authPluginRuntimeConformanceMagicLinkToken,
          ),
          headers: <String, List<String>>{
            'cookie': <String>[concurrentCookie],
          },
        ),
      ),
    ),
  );
  _check(
    concurrent.where((response) => response.statusCode == 200).length == 1,
    'magic-link.concurrent-replay',
    'Concurrent callback attempts did not have exactly one winner.',
  );
  for (final response in concurrent.where(
    (response) => response.statusCode != 200,
  )) {
    _expectError(
      response,
      caseId: 'magic-link.concurrent-replay',
      statusCode: 401,
      error: 'invalid_token',
    );
  }
}

Future<T> _clientOperation<T>(
  Future<T> Function() operation, {
  required String caseId,
}) async {
  try {
    return await operation();
  } on AuthClientException catch (exception) {
    throw AuthRuntimeConformanceFailure(
      caseId: caseId,
      message: 'The host returned ${exception.statusCode}/${exception.code}.',
    );
  }
}

Future<void> _expectMagicLinkClientError(
  Future<Object?> Function() operation, {
  required String caseId,
  required int statusCode,
  required String error,
}) async {
  try {
    await operation();
  } on AuthClientException catch (exception) {
    _check(
      exception.statusCode == statusCode && exception.code == error,
      caseId,
      'Expected $statusCode/$error, received '
      '${exception.statusCode}/${exception.code}.',
    );
    return;
  }
  throw AuthRuntimeConformanceFailure(
    caseId: caseId,
    message: 'The typed client unexpectedly accepted the request.',
  );
}

Future<void> _verifyPhoneNumber(
  AuthRuntimeConformanceSend send,
  Uri origin,
  AuthPluginRuntimePhoneDeliveryRecorder deliveryRecorder,
) async {
  const phonePlugin = AuthPhoneNumberClientPlugin();
  const sessionPlugin = AuthSessionClientPlugin();
  final transport = _AuthRuntimeConformanceHttpClient(send);
  final client = AuthClient(
    baseUrl: origin,
    httpClient: transport,
    headers: <String, String>{
      'origin': origin.toString(),
      'sec-fetch-site': 'same-origin',
    },
    plugins: const <AuthClientPlugin<dynamic>>[phonePlugin, sessionPlugin],
  );
  final phone = client.plugins.use(phonePlugin);

  final deliveriesBefore = deliveryRecorder.deliveries.length;
  final issued = await phone.sendCode(
    phoneNumber: authPluginRuntimeConformancePhoneNumber,
  );
  final deliveries = deliveryRecorder
      .forPhone(authPluginRuntimeConformancePhoneNumber)
      .toList(growable: false);
  _check(
    deliveryRecorder.deliveries.length == deliveriesBefore + 1 &&
        deliveries.length == 1 &&
        deliveries.single.code == _authPluginRuntimeConformancePhoneCode &&
        deliveries.single.expiresAt == issued.expiresAt,
    'phone.delivery',
    'The server plugin did not invoke its provider-owned delivery callback.',
  );
  _check(
    transport.requestPaths.contains('/auth/phone-number/send-code'),
    'phone.send.path',
    'The typed phone client did not use the exact send-code route.',
  );
  _check(
    !transport.requestPaths.contains('/auth/csrf'),
    'phone.csrf',
    'The CSRF-exempt phone operation unexpectedly requested a CSRF token.',
  );
  _assertPhoneCodeSecret(transport.responses, 'phone.send.secret');

  final crossOrigin = await send(
    AuthRuntimeConformanceRequest(
      method: 'POST',
      path: '/auth/phone-number/send-code',
      headers: _jsonHeaders(origin: 'https://attacker.runtime.test'),
      body: jsonEncode(<String, Object?>{'phoneNumber': '+18765550106'}),
    ),
  );
  _expectError(
    crossOrigin,
    caseId: 'phone.origin',
    statusCode: 403,
    error: 'invalid_origin',
  );

  for (final hostilePhone in _hostilePhoneNumbers()) {
    final response = await send(
      AuthRuntimeConformanceRequest(
        method: 'POST',
        path: '/auth/phone-number/send-code',
        headers: _jsonHeaders(origin: origin.toString()),
        body: jsonEncode(<String, Object?>{'phoneNumber': hostilePhone}),
      ),
    );
    _expectError(
      response,
      caseId: 'phone.hostile-number',
      statusCode: 400,
      error: 'invalid_phone_number',
    );
    _check(
      !response.body.contains(hostilePhone) &&
          !response.body.contains('StateError') &&
          !response.body.contains('/src/'),
      'phone.hostile-number',
      'A hostile phone number reached the public error response.',
    );
  }

  final providerFailure = await send(
    AuthRuntimeConformanceRequest(
      method: 'POST',
      path: '/auth/phone-number/send-code',
      headers: _jsonHeaders(origin: origin.toString()),
      body: jsonEncode(<String, Object?>{
        'phoneNumber': _authPluginRuntimePhoneDeliveryFailureNumber,
      }),
    ),
  );
  _expectError(
    providerFailure,
    caseId: 'phone.delivery-failure',
    statusCode: 400,
    error: 'auth_request_failed',
  );
  _check(
    !providerFailure.body.contains(
          _authPluginRuntimePhoneDeliveryFailureMarker,
        ) &&
        !providerFailure.body.contains(_authPluginRuntimeConformancePhoneCode),
    'phone.delivery-failure',
    'Provider diagnostics or the raw code leaked into the public response.',
  );

  const hostileCodePhone = '+18765550103';
  await phone.sendCode(phoneNumber: hostileCodePhone);
  for (final hostileCode in _hostilePhoneCodes()) {
    await _expectAuthClientError(
      () => phone.verifyCode(phoneNumber: hostileCodePhone, code: hostileCode),
      caseId: 'phone.hostile-code',
      statusCode: 401,
      error: 'invalid_phone_code',
    );
    _check(
      transport.responses.last.body.contains(hostileCode) == false,
      'phone.hostile-code',
      'A hostile verification code reached the public error response.',
    );
  }

  const lockoutPhone = '+18765550104';
  await phone.sendCode(phoneNumber: lockoutPhone);
  for (var attempt = 0; attempt < 3; attempt++) {
    await _expectAuthClientError(
      () => phone.verifyCode(phoneNumber: lockoutPhone, code: '000000'),
      caseId: 'phone.lockout',
      statusCode: attempt < 2 ? 401 : 403,
      error: attempt < 2
          ? 'invalid_phone_code'
          : 'phone_code_too_many_attempts',
    );
  }

  final verified = await phone.verifyCode(
    phoneNumber: authPluginRuntimeConformancePhoneNumber,
    code: _authPluginRuntimeConformancePhoneCode,
    name: 'Runtime Phone User',
  );
  _check(
    verified.phoneNumber == authPluginRuntimeConformancePhoneNumber &&
        verified.session.user.attributes['phoneNumber'] ==
            authPluginRuntimeConformancePhoneNumber &&
        verified.session.user.attributes['phoneNumberVerified'] == true,
    'phone.verify',
    'The typed phone client did not return the verified phone session.',
  );
  _check(
    transport.requestPaths.contains('/auth/phone-number/verify-code'),
    'phone.verify.path',
    'The typed phone client did not use the exact verify-code route.',
  );
  final current = await client.plugins.use(sessionPlugin).current();
  _check(
    current?.user.id == verified.session.user.id,
    'phone.session',
    'The host-issued cookie was not readable through the session client.',
  );
  await _expectAuthClientError(
    () => phone.verifyCode(
      phoneNumber: authPluginRuntimeConformancePhoneNumber,
      code: _authPluginRuntimeConformancePhoneCode,
    ),
    caseId: 'phone.replay',
    statusCode: 401,
    error: 'invalid_phone_code',
  );

  const concurrentPhone = '+18765550105';
  await phone.sendCode(phoneNumber: concurrentPhone);
  final concurrent = await Future.wait(
    List<Future<AuthRuntimeConformanceResponse>>.generate(
      8,
      (_) => send(
        AuthRuntimeConformanceRequest(
          method: 'POST',
          path: '/auth/phone-number/verify-code',
          headers: _jsonHeaders(origin: origin.toString()),
          body: jsonEncode(<String, Object?>{
            'phoneNumber': concurrentPhone,
            'code': _authPluginRuntimeConformancePhoneCode,
          }),
        ),
      ),
    ),
  );
  _check(
    concurrent.where((response) => response.statusCode == 200).length == 1,
    'phone.concurrent-replay',
    'Concurrent verification attempts did not have exactly one winner.',
  );
  for (final response in concurrent.where(
    (response) => response.statusCode != 200,
  )) {
    _expectError(
      response,
      caseId: 'phone.concurrent-replay',
      statusCode: 401,
      error: 'invalid_phone_code',
    );
  }
  _assertPhoneCodeSecret(<AuthRuntimeConformanceResponse>[
    ...transport.responses,
    ...concurrent,
  ], 'phone.response-secrecy');
}

Future<void> _expectAuthClientError(
  Future<Object?> Function() operation, {
  required String caseId,
  required int statusCode,
  required String error,
}) async {
  try {
    await operation();
  } on AuthClientException catch (exception) {
    _check(
      exception.statusCode == statusCode && exception.code == error,
      caseId,
      'Expected $statusCode/$error, received '
      '${exception.statusCode}/${exception.code}.',
    );
    return;
  }
  throw AuthRuntimeConformanceFailure(
    caseId: caseId,
    message: 'The typed client unexpectedly accepted the request.',
  );
}

void _assertPhoneCodeSecret(
  Iterable<AuthRuntimeConformanceResponse> responses,
  String caseId,
) {
  _check(
    responses.every(
      (response) =>
          !response.body.contains(_authPluginRuntimeConformancePhoneCode),
    ),
    caseId,
    'The raw provider-delivered phone code leaked into an HTTP response.',
  );
}

Iterable<String> _hostilePhoneNumbers() sync* {
  yield '18765550101';
  yield '+08765550101';
  yield '+1 876 555 0101';
  yield '+1-876-555-0101';
  yield '+1\r\nSet-Cookie: owned=true';
  yield '+1\u0000Authorization: Bearer secret';
  yield '+١٨٧٦٥٥٥٠١٠١';
  yield '<script>alert(1)</script>';
  yield "' OR '1'='1";
  yield '+${List<String>.filled(256, '9').join()}';
}

Iterable<String> _hostilePhoneCodes() sync* {
  yield 'wrong-code';
  yield '12345';
  yield '1234567';
  yield '１２３４５６';
  yield '123 456';
  yield '123-456';
  yield '\r\nSet-Cookie: owned=true';
  yield '\u0000authorization: bearer secret';
  yield '<script>alert(1)</script>';
  yield "' OR '1'='1";
  yield List<String>.filled(256, '9').join();
}

Future<String> _authClientCookieHeader(AuthClientCookieStore store) async {
  final cookies = await Future.sync(store.load);
  final header = cookies
      .where((cookie) => !cookie.isDeletion)
      .map((cookie) => '${cookie.name}=${cookie.value}')
      .join('; ');
  _check(
    header.isNotEmpty,
    'magic-link.cookies',
    'The typed client did not retain the host session and browser binding.',
  );
  return header;
}

String _magicLinkCallbackPath(String token) {
  final route = authCallbackProviderRoute.resolve(
    <AuthRouteParameterKey, String>{
      authProviderRouteParameter:
          authPluginRuntimeConformanceMagicLinkProviderId,
    },
  );
  return Uri(
    path: '/auth$route',
    queryParameters: <String, String>{
      'email': authPluginRuntimeConformanceMagicLinkEmail,
      'token': token,
    },
  ).toString();
}

Iterable<String> _hostileMagicLinkTokens() sync* {
  yield 'wrong-token';
  yield '../callback/runtime-email';
  yield '%0d%0aSet-Cookie:owned=true';
  yield '\u0000authorization: bearer secret';
  yield '\u202eelpmaxe.rekcatta//:sptth';
  yield '<script>alert(1)</script>';
  for (var index = 0; index < 24; index++) {
    yield 'invalid-$index-${List<String>.filled(index + 1, 'x').join()}';
  }
}

final class _AuthRuntimeConformanceHttpClient extends http.BaseClient {
  _AuthRuntimeConformanceHttpClient(this._dispatch);

  final AuthRuntimeConformanceSend _dispatch;
  final List<Uri> requests = <Uri>[];
  final List<AuthRuntimeConformanceResponse> responses =
      <AuthRuntimeConformanceResponse>[];

  Iterable<String> get requestPaths => requests.map((request) => request.path);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request.url);
    final bytes = await request.finalize().toBytes();
    final response = await _dispatch(
      AuthRuntimeConformanceRequest(
        method: request.method,
        path: request.url.hasQuery
            ? '${request.url.path}?${request.url.query}'
            : request.url.path,
        headers: request.headers.map(
          (name, value) => MapEntry(name, <String>[value]),
        ),
        body: bytes.isEmpty ? null : utf8.decode(bytes),
      ),
    );
    responses.add(response);
    return http.StreamedResponse(
      Stream<Uint8List>.value(Uint8List.fromList(utf8.encode(response.body))),
      response.statusCode,
      headers: response.headers.map(
        (name, values) => MapEntry(name, values.join(', ')),
      ),
      request: request,
    );
  }
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
