import 'dart:convert';
import 'dart:io';

import 'package:routed_auth/routed_auth.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

import '../test_engine.dart';

const _rateLimitHashKey = 'email-otp-route-test-key-not-for-production-use';

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

final class _EmailOtpLimiter implements AuthRateLimiter<EngineContext> {
  final List<AuthRateLimitRequest<EngineContext>> requests = [];

  @override
  AuthRateLimitDecision check(AuthRateLimitRequest<EngineContext> request) {
    requests.add(request);
    return const AuthRateLimitDecision.allow();
  }
}

void main() {
  test(
    'email OTP routes use a keyed target limiter without leaking request secrets',
    () async {
      final limiter = _EmailOtpLimiter();
      final plugin = EmailOtpPlugin<EngineContext>(
        rateLimitHashKey: _rateLimitHashKey,
        generateOtp: (_) => '123456',
        sendCode: (_) {},
      );
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: const [],
          plugins: [plugin],
          rateLimiter: limiter,
        ),
      );
      final engine = testEngine(
        config: EngineConfig(
          security: const EngineSecurityFeatures(csrfProtection: false),
        ),
      );
      AuthRoutes(manager).register(engine.defaultRouter);
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);

      final sent = await client.postJson(
        '/auth/email-otp/send-verification-otp',
        const <String, dynamic>{
          'email': ' Ada@Example.COM ',
          'type': 'sign-in',
        },
      );
      sent.assertStatus(HttpStatus.ok);
      final checked = await client.postJson(
        '/auth/email-otp/check-verification-otp',
        const <String, dynamic>{
          'email': 'ada@example.com',
          'type': 'sign-in',
          'otp': '123456',
        },
      );
      checked.assertStatus(HttpStatus.ok);

      expect(limiter.requests, hasLength(2));
      final sendRequest = limiter.requests.first;
      final checkRequest = limiter.requests.last;
      expect(sendRequest.providerId, authEmailOtpPluginId);
      expect(checkRequest.providerId, authEmailOtpPluginId);
      expect(sendRequest.providerId, sendRequest.operation.namespace);
      expect(checkRequest.providerId, checkRequest.operation.namespace);
      expect(sendRequest.identifier, checkRequest.identifier);
      expect(sendRequest.identifier, startsWith('email:'));
      expect(
        sendRequest.identifier!.length,
        lessThanOrEqualTo(authRateLimitIdentifierMaximumLength),
      );
      expect(sendRequest.identifier, isNot(contains('ada@example.com')));
      expect(checkRequest.identifier, isNot(contains('123456')));

      final malformed = await client.postJson(
        '/auth/email-otp/check-verification-otp',
        const <String, dynamic>{'type': 'sign-in', 'otp': '123456'},
      );
      malformed.assertStatus(HttpStatus.unauthorized);
      expect(malformed.json(), const <String, dynamic>{
        'error': 'invalid_request',
      });
      expect(limiter.requests.last.identifier, isNull);
    },
  );

  test(
    'email OTP sign-in rejects cross-origin forms but allows same-origin and native clients',
    () async {
      String? sentCode;
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: const [],
          plugins: [
            EmailOtpPlugin<EngineContext>(
              rateLimitHashKey: _rateLimitHashKey,
              generateOtp: (_) => '123456',
              sendCode: (delivery) => sentCode = delivery.code,
            ),
          ],
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
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);

      Future<void> sendOtp() async {
        final sent = await client.postJson(
          '/auth/email-otp/send-verification-otp',
          const <String, dynamic>{
            'email': 'browser@example.com',
            'type': 'sign-in',
          },
        );
        sent.assertStatus(HttpStatus.ok);
        expect(sentCode, '123456');
      }

      await sendOtp();
      final formBody = Uri(
        queryParameters: <String, String>{
          'email': 'browser@example.com',
          'otp': sentCode!,
        },
      ).query;
      final crossOrigin = await client.post(
        '/auth/sign-in/email-otp',
        formBody,
        headers: const <String, List<String>>{
          HttpHeaders.contentTypeHeader: ['application/x-www-form-urlencoded'],
          'Origin': ['https://attacker.example'],
          'Sec-Fetch-Site': ['cross-site'],
        },
      );
      crossOrigin.assertStatus(HttpStatus.forbidden);
      expect(crossOrigin.json(), <String, dynamic>{'error': 'invalid_origin'});

      final sameOrigin = await client.post(
        '/auth/sign-in/email-otp',
        formBody,
        headers: const <String, List<String>>{
          HttpHeaders.contentTypeHeader: ['application/x-www-form-urlencoded'],
          'Origin': ['http://server_testing.internal'],
          'Sec-Fetch-Site': ['same-origin'],
        },
      );
      sameOrigin.assertStatus(HttpStatus.ok);
      expect(sameOrigin.json()['user']['email'], 'browser@example.com');

      await sendOtp();
      final native = await client.postJson(
        '/auth/sign-in/email-otp',
        <String, dynamic>{'email': 'browser@example.com', 'otp': sentCode},
      );
      native.assertStatus(HttpStatus.ok);
      expect(native.json()['user']['email'], 'browser@example.com');
    },
  );

  test(
    'email OTP routes send, sign in, and verify with typed sessions',
    () async {
      String? sentCode;
      final feature = EmailOtpPlugin<EngineContext>(
        rateLimitHashKey: _rateLimitHashKey,
        generateOtp: (_) => '123456',
        sendCode: (delivery) {
          sentCode = delivery.code;
        },
      );
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

      final sent = await client.postJson(
        '/auth/email-otp/send-verification-otp',
        {'email': 'ada@example.com', 'type': 'sign-in'},
      );
      sent.assertStatus(HttpStatus.ok);
      expect(sent.json()['status'], 'verification_sent');
      expect(sent.body, isNot(contains('123456')));

      final signedIn = await client.postJson('/auth/sign-in/email-otp', {
        'email': 'ADA@EXAMPLE.COM',
        'otp': sentCode,
      });
      signedIn.assertStatus(HttpStatus.ok);
      expect(signedIn.json()['user']['email'], 'ada@example.com');
      final sessionCookie = signedIn.cookie('test_session');
      expect(sessionCookie, isNotNull);

      final session = await client.get(
        '/auth/session',
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie!)],
        },
      );
      session.assertStatus(HttpStatus.ok);
      expect(session.json()['user']['id'], signedIn.json()['user']['id']);

      final verification = await client.postJson(
        '/auth/email-otp/send-verification-otp',
        {'email': 'ada@example.com', 'type': 'email-verification'},
      );
      verification.assertStatus(HttpStatus.ok);
      final csrf = await client.get(
        '/auth/csrf',
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
        },
      );
      csrf.assertStatus(HttpStatus.ok);
      final verified = await client.postJson(
        '/auth/email-otp/verify-email',
        {'otp': sentCode, '_csrf': csrf.json()['csrfToken']},
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(sessionCookie)],
        },
      );
      verified.assertStatus(HttpStatus.ok);
      expect(verified.json()['user']['attributes']['emailVerified'], isTrue);
    },
  );

  test('invalid email OTP stays a bounded auth error', () async {
    final feature = EmailOtpPlugin<EngineContext>(
      rateLimitHashKey: _rateLimitHashKey,
      sendCode: (delivery) async {},
    );
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        providers: const [],
        plugins: [feature],
      ),
    );
    final engine = testEngine(
      config: EngineConfig(
        security: EngineSecurityFeatures(csrfProtection: false),
      ),
    );
    AuthRoutes(manager).register(engine.defaultRouter);
    await engine.initialize();
    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(client.close);

    final response = await client.postJson('/auth/sign-in/email-otp', {
      'email': 'ada@example.com',
      'otp': '000000',
    });
    response.assertStatus(HttpStatus.unauthorized);
    expect(response.json(), {'error': 'invalid_otp'});
  });
}
