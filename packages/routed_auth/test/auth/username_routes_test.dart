import 'dart:convert';
import 'dart:io';

import 'package:routed_auth/routed_auth.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

import '../test_engine.dart';

final class _Hasher implements PasswordHasher {
  @override
  String hash(String password) => 'hash:$password';

  @override
  PasswordVerification verify(String password, String encodedHash) =>
      PasswordVerification(
        matches: encodedHash == 'hash:$password',
        needsRehash: false,
      );
}

final class _Limiter implements AuthRateLimiter<EngineContext> {
  final List<AuthRateLimitRequest<EngineContext>> requests = [];
  bool blocked = false;

  @override
  AuthRateLimitDecision check(AuthRateLimitRequest<EngineContext> request) {
    requests.add(request);
    return blocked
        ? const AuthRateLimitDecision.block(retryAfter: Duration(seconds: 15))
        : const AuthRateLimitDecision.allow();
  }
}

final class _Captcha implements AuthCaptchaVerifier<EngineContext> {
  _Captcha(this.events);

  final List<String> events;

  @override
  AuthCaptchaVerificationResult verify(
    AuthCaptchaVerificationRequest<EngineContext> request,
  ) {
    events.add('captcha:${request.identifier}');
    return const AuthCaptchaVerificationResult.accepted();
  }
}

void main() {
  test(
    'username plugin routes register, sign in, protect, and rate-limit canonically',
    () async {
      final events = <String>[];
      final limiter = _Limiter();
      final store = InMemoryAuthStore();
      final username = UsernamePlugin<EngineContext>();
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          providers: const <AuthProvider>[],
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          passwordHasher: _Hasher(),
          rateLimiter: limiter,
          plugins: <AuthServerPlugin<EngineContext>>[
            username,
            CaptchaPlugin<EngineContext>(verifier: _Captcha(events)),
          ],
        ),
      );
      final fixture = await _fixture(manager);

      const password = 'safe-password-123';
      const captcha = 'opaque-captcha-secret';
      final registered = await fixture.client
          .postJson('/auth/username/register', const <String, dynamic>{
            'username': ' Routed.User ',
            'email': 'ROUTED@EXAMPLE.COM',
            'password': password,
            'captchaToken': captcha,
          });
      registered.assertStatus(HttpStatus.ok);
      expect(registered.json()['status'], 'authenticated');
      expect(registered.json()['username'], 'routed.user');
      expect(registered.json()['user']['email'], 'routed@example.com');
      expect(registered.body, isNot(contains(password)));
      expect(registered.body, isNot(contains(captcha)));
      expect(registered.cookie('username_session'), isNotNull);
      expect(limiter.requests.single.identifier, 'routed.user');
      expect(limiter.requests.single.providerId, authUsernamePluginId);
      expect(
        limiter.requests.single.providerId,
        limiter.requests.single.operation.namespace,
      );
      expect(
        limiter.requests.single.identifier!.length,
        lessThanOrEqualTo(authRateLimitIdentifierMaximumLength),
      );
      expect(
        limiter.requests.single.operation,
        authUsernameRegistrationRateLimitOperation,
      );
      expect(events, ['captcha:routed.user']);

      final userId = registered.json()['user']['id'] as String;
      final sessions = await store.sessions.listForUser(userId);
      expect(
        sessions.single.authenticationMethod,
        authUsernameAuthenticationMethod,
      );

      final signedIn = await fixture.client
          .postJson('/auth/username/sign-in', const <String, dynamic>{
            'identifier': 'ROUTED@EXAMPLE.COM',
            'password': password,
            'captchaToken': captcha,
          });
      signedIn.assertStatus(HttpStatus.ok);
      expect(signedIn.json()['user']['id'], userId);
      expect(limiter.requests.last.identifier, 'routed@example.com');
      expect(limiter.requests.last.providerId, authUsernamePluginId);
      expect(
        limiter.requests.last.operation,
        authUsernameSignInRateLimitOperation,
      );

      final unknown = await fixture.client
          .postJson('/auth/username/sign-in', const <String, dynamic>{
            'identifier': 'unknown@example.com',
            'password': password,
            'captchaToken': captcha,
          });
      unknown.assertStatus(HttpStatus.unauthorized);
      expect(unknown.json(), <String, dynamic>{'error': 'invalid_credentials'});

      limiter.blocked = true;
      final blocked = await fixture.client.postJson(
        '/auth/username/sign-in',
        const <String, dynamic>{
          'identifier': 'Routed.User',
          'password': password,
          'captchaToken': captcha,
        },
      );
      blocked.assertStatus(HttpStatus.tooManyRequests);
      expect(blocked.json(), <String, dynamic>{'error': 'rate_limited'});
      expect(blocked.headers[HttpHeaders.retryAfterHeader], contains('15'));
      expect(limiter.requests.last.identifier, 'routed.user');
    },
  );

  test('username route returns a typed pending two-factor challenge', () async {
    var sequence = 0;
    final twoFactor = TwoFactorPlugin<EngineContext>(
      store: InMemoryAuthTwoFactorStore(),
      challengeStore: InMemoryAuthTwoFactorChallengeStore(),
      trustedDeviceStore: InMemoryAuthTwoFactorTrustedDeviceStore(),
      secretProtector: const PlaintextAuthTwoFactorSecretProtector(),
      secretGenerator: (length) {
        final current = sequence++;
        return List<int>.generate(
          length,
          (index) => (current * 31 + index + 1) & 0xff,
        );
      },
    );
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        providers: const <AuthProvider>[],
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        passwordHasher: _Hasher(),
        plugins: <AuthServerPlugin<EngineContext>>[
          UsernamePlugin<EngineContext>(),
          twoFactor,
        ],
      ),
    );
    final fixture = await _fixture(manager);
    final registered = await fixture.client.postJson(
      '/auth/username/register',
      const <String, dynamic>{
        'username': 'mfa-user',
        'password': 'safe-password-123',
      },
    );
    registered.assertStatus(HttpStatus.ok);
    final userId = registered.json()['user']['id'] as String;
    final now = DateTime.now().toUtc();
    final enrollment = await twoFactor.beginEnrollment(userId, now: now);
    final code = generateAuthTotpCode(
      enrollment.secret,
      timestampSeconds: now.millisecondsSinceEpoch ~/ 1000,
    );
    await twoFactor.verifyEnrollment(userId, code, now: now);

    final challenged = await fixture.client.postJson(
      '/auth/username/sign-in',
      const <String, dynamic>{
        'identifier': 'mfa-user',
        'password': 'safe-password-123',
      },
    );
    challenged.assertStatus(HttpStatus.accepted);
    expect(challenged.json()['status'], 'two_factor_required');
    expect(challenged.json()['challengeToken'], isNotEmpty);
    expect(
      DateTime.tryParse(challenged.json()['expiresAt'] as String),
      isNotNull,
    );
  });
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
    cookieName: 'username_session',
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
