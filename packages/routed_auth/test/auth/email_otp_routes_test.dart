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
  test(
    'email OTP routes send, sign in, and verify with typed sessions',
    () async {
      String? sentCode;
      final feature = EmailOtpFeature<EngineContext>(
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
          features: [feature],
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
    final feature = EmailOtpFeature<EngineContext>(
      sendCode: (delivery) async {},
    );
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        providers: const [],
        features: [feature],
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
