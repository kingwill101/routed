import 'dart:convert';
import 'dart:io';

import 'package:routed_auth/routed_auth.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

import '../test_engine.dart';

const _hashKey = '0123456789abcdef0123456789abcdef';

void main() {
  test(
    'phone routes deliver, verify, and issue a phone-number session',
    () async {
      final phoneStore = InMemoryAuthPhoneNumberStore();
      final coreStore = InMemoryAuthStore();
      String? deliveredCode;
      final plugin = PhoneNumberPlugin<EngineContext>(
        store: phoneStore,
        codeHashKey: _hashKey,
        allowSignUp: true,
        generateCode: (_) => '123456',
        sendCode: (delivery) => deliveredCode = delivery.code,
      );
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: coreStore,
          storeMode: AuthStoreMode.ephemeral,
          providers: const <AuthProvider>[],
          plugins: <AuthServerPlugin<EngineContext>>[plugin],
        ),
      );
      final fixture = await _fixture(manager);

      expect(manager.phoneNumbers, same(plugin));
      final sent = await fixture.client.postJson(
        '/auth/phone-number/send-code',
        {'phoneNumber': ' +18765551234 '},
      );
      sent.assertStatus(HttpStatus.ok);
      expect(sent.json()['status'], 'verification_sent');
      expect(sent.body, isNot(contains('123456')));
      expect(deliveredCode, '123456');

      final verified = await fixture.client.postJson(
        '/auth/phone-number/verify-code',
        <String, dynamic>{
          'phoneNumber': '+18765551234',
          'code': deliveredCode,
          'name': 'Ada',
        },
      );
      verified.assertStatus(HttpStatus.ok);
      expect(verified.json()['status'], 'authenticated');
      expect(verified.json()['phoneNumber'], '+18765551234');
      expect(
        verified.json()['user']['attributes']['phoneNumberVerified'],
        isTrue,
      );
      expect(verified.cookie('phone_session'), isNotNull);

      final userId = verified.json()['user']['id'] as String;
      final sessions = await coreStore.sessions.listForUser(userId);
      expect(sessions, hasLength(1));
      expect(
        sessions.single.authenticationMethod,
        authPhoneNumberAuthenticationMethod,
      );

      final replay = await fixture.client.postJson(
        '/auth/phone-number/verify-code',
        <String, dynamic>{'phoneNumber': '+18765551234', 'code': deliveredCode},
      );
      replay.assertStatus(HttpStatus.unauthorized);
      expect(replay.json(), <String, dynamic>{'error': 'invalid_phone_code'});
    },
  );

  test(
    'bounded attempts and rate-limit descriptors remain public-safe',
    () async {
      final limiter = _PhoneRateLimiter();
      final plugin = PhoneNumberPlugin<EngineContext>(
        store: InMemoryAuthPhoneNumberStore(),
        codeHashKey: _hashKey,
        allowedAttempts: 2,
        generateCode: (_) => '123456',
        sendCode: (_) {},
      );
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: const <AuthProvider>[],
          plugins: <AuthServerPlugin<EngineContext>>[plugin],
          rateLimiter: limiter,
        ),
      );
      final fixture = await _fixture(manager);

      await fixture.client.postJson('/auth/phone-number/send-code', {
        'phoneNumber': ' +18765551234 ',
      });
      for (var attempt = 0; attempt < 2; attempt++) {
        final response = await fixture.client.postJson(
          '/auth/phone-number/verify-code',
          const <String, dynamic>{
            'phoneNumber': '+18765551234',
            'code': '000000',
          },
        );
        response.assertStatus(
          attempt == 0 ? HttpStatus.unauthorized : HttpStatus.forbidden,
        );
      }
      expect(
        limiter.operations,
        contains(authPhoneNumberSendRateLimitOperation),
      );
      expect(
        limiter.operations,
        contains(authPhoneNumberVerifyRateLimitOperation),
      );
      final sendRequest = limiter.requests.first;
      final verifyRequest = limiter.requests[1];
      expect(sendRequest.providerId, authPhoneNumberPluginId);
      expect(verifyRequest.providerId, authPhoneNumberPluginId);
      expect(sendRequest.providerId, sendRequest.operation.namespace);
      expect(verifyRequest.providerId, verifyRequest.operation.namespace);
      expect(sendRequest.identifier, verifyRequest.identifier);
      expect(sendRequest.identifier, startsWith('phone:'));
      expect(
        sendRequest.identifier!.length,
        lessThanOrEqualTo(authRateLimitIdentifierMaximumLength),
      );
      expect(sendRequest.identifier, isNot(contains('+18765551234')));
      expect(verifyRequest.identifier, isNot(contains('000000')));

      final malformed = await fixture.client.postJson(
        '/auth/phone-number/verify-code',
        const <String, dynamic>{'phoneNumber': '+18765551234'},
      );
      malformed.assertStatus(HttpStatus.unauthorized);
      expect(malformed.json(), const <String, dynamic>{
        'error': 'invalid_request',
      });
      expect(limiter.requests.last.identifier, isNull);

      limiter.blockVerify = true;
      final blocked = await fixture.client.postJson(
        '/auth/phone-number/verify-code',
        const <String, dynamic>{
          'phoneNumber': '+18765551234',
          'code': '123456',
        },
      );
      blocked.assertStatus(HttpStatus.tooManyRequests);
      expect(blocked.json(), <String, dynamic>{'error': 'rate_limited'});
      expect(blocked.headers[HttpHeaders.retryAfterHeader], contains('30'));
    },
  );

  test(
    'delivery failures and malformed input do not leak diagnostics',
    () async {
      const secretMarker = '/srv/secrets/sms-provider.key';
      final plugin = PhoneNumberPlugin<EngineContext>(
        store: InMemoryAuthPhoneNumberStore(),
        codeHashKey: _hashKey,
        generateCode: (_) => '123456',
        sendCode: (_) => throw StateError('$secretMarker raw=123456'),
      );
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: const <AuthProvider>[],
          plugins: <AuthServerPlugin<EngineContext>>[plugin],
        ),
      );
      final fixture = await _fixture(manager);

      final failed = await fixture.client.postJson(
        '/auth/phone-number/send-code',
        const <String, dynamic>{'phoneNumber': '+18765551234'},
      );
      expect(failed.body, isNot(contains(secretMarker)));
      expect(failed.body, isNot(contains('123456')));
      expect(failed.json(), <String, dynamic>{'error': 'auth_request_failed'});

      const hostile = '+1\r\nSet-Cookie: attacker=true';
      final malformed = await fixture.client.postJson(
        '/auth/phone-number/send-code',
        const <String, dynamic>{'phoneNumber': hostile},
      );
      malformed.assertStatus(HttpStatus.badRequest);
      expect(malformed.json(), <String, dynamic>{
        'error': 'invalid_phone_number',
      });
      expect(malformed.body, isNot(contains(hostile)));
    },
  );
}

Future<_Fixture> _fixture(AuthManager manager) async {
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
  addTearDown(() async {
    await client.close();
    await engine.close();
  });
  return _Fixture(client);
}

SessionConfig _sessionConfig() {
  final key = base64.encode(List<int>.generate(32, (index) => index + 1));
  return SessionConfig.cookie(
    appKey: 'base64:$key',
    cookieName: 'phone_session',
    options: SessionOptions(
      path: '/',
      secure: false,
      httpOnly: true,
      sameSite: SameSite.lax,
    ),
  );
}

final class _Fixture {
  const _Fixture(this.client);

  final TestClient client;
}

final class _PhoneRateLimiter implements AuthRateLimiter<EngineContext> {
  final List<AuthRateLimitRequest<EngineContext>> requests =
      <AuthRateLimitRequest<EngineContext>>[];
  Iterable<AuthRateLimitOperation> get operations =>
      requests.map((request) => request.operation);
  bool blockVerify = false;

  @override
  AuthRateLimitDecision check(AuthRateLimitRequest<EngineContext> request) {
    requests.add(request);
    if (blockVerify &&
        request.operation == authPhoneNumberVerifyRateLimitOperation) {
      return const AuthRateLimitDecision.block(
        retryAfter: Duration(seconds: 30),
      );
    }
    return const AuthRateLimitDecision.allow();
  }
}
