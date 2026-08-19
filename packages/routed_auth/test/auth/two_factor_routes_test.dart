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

Engine _authEngine(AuthManager manager) {
  final engine = testEngine(
    config: EngineConfig(
      security: const EngineSecurityFeatures(csrfProtection: false),
    ),
    providers: [RoutedSessionsProvider(_sessionConfig())],
  );
  engine.addGlobalMiddleware(sessionMiddleware());
  engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());
  AuthRoutes(manager).register(engine.defaultRouter);
  return engine;
}

String _cookieHeader(Cookie cookie) => '${cookie.name}=${cookie.value}';

final class _BlockingAuthLimiter implements AuthRateLimiter<EngineContext> {
  AuthRateLimitRequest<EngineContext>? lastRequest;

  @override
  AuthRateLimitDecision check(AuthRateLimitRequest<EngineContext> request) {
    lastRequest = request;
    return const AuthRateLimitDecision.block(retryAfter: Duration(seconds: 17));
  }
}

Argon2idPasswordHasher _testHasher() =>
    Argon2idPasswordHasher(iterations: 1, memoryKiB: 8, derivedKeyLength: 16);

void main() {
  test(
    'registers two-factor routes before a manager reload enables the feature',
    () async {
      final initialManager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [CredentialsProvider()],
        ),
      );
      final reloadedManager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [CredentialsProvider()],
          features: [
            TwoFactorFeature<EngineContext>(
              store: InMemoryAuthTwoFactorStore(),
              challengeStore: InMemoryAuthTwoFactorChallengeStore(),
              trustedDeviceStore: InMemoryAuthTwoFactorTrustedDeviceStore(),
              stepUpStore: InMemoryAuthTwoFactorStepUpStore(),
              secretProtector: const PlaintextAuthTwoFactorSecretProtector(),
            ),
          ],
        ),
      );
      var currentManager = initialManager;
      final engine = testEngine(
        config: EngineConfig(
          security: const EngineSecurityFeatures(csrfProtection: false),
        ),
        providers: [RoutedSessionsProvider(_sessionConfig())],
      );
      engine.addGlobalMiddleware(sessionMiddleware());
      engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());
      AuthRoutes(
        initialManager,
        managerOf: () => currentManager,
      ).register(engine.defaultRouter);
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);

      currentManager = reloadedManager;
      final response = await client.get('/auth/2fa/status');

      response.assertStatus(HttpStatus.unauthorized);
      expect(response.json()['error'], equals('unauthorized'));
    },
  );

  test('applies the global rate limiter to two-factor routes', () async {
    final limiter = _BlockingAuthLimiter();
    final feature = TwoFactorFeature<EngineContext>(
      store: InMemoryAuthTwoFactorStore(),
      challengeStore: InMemoryAuthTwoFactorChallengeStore(),
      trustedDeviceStore: InMemoryAuthTwoFactorTrustedDeviceStore(),
      stepUpStore: InMemoryAuthTwoFactorStepUpStore(),
      secretProtector: const PlaintextAuthTwoFactorSecretProtector(),
    );
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        providers: [CredentialsProvider()],
        features: [feature],
        rateLimiter: limiter,
      ),
    );
    final engine = _authEngine(manager);
    await engine.initialize();
    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(client.close);

    final csrfResponse = await client.get('/auth/csrf');
    final csrf = csrfResponse.json()['csrfToken'] as String;
    final csrfCookie = csrfResponse.cookie('test_session')!;
    final response = await client.postJson(
      '/auth/2fa/challenge/verify',
      {'challengeToken': 'challenge-1', 'code': '123456', '_csrf': csrf},
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(csrfCookie)],
      },
    );
    response.assertStatus(HttpStatus.tooManyRequests);
    expect(response.json()['error'], equals('rate_limited'));
    expect(limiter.lastRequest?.action, AuthRateLimitAction.twoFactor);
  });

  test(
    'continues the original callback credential flow after TOTP verification',
    () async {
      final feature = TwoFactorFeature<EngineContext>(
        store: InMemoryAuthTwoFactorStore(),
        challengeStore: InMemoryAuthTwoFactorChallengeStore(),
        trustedDeviceStore: InMemoryAuthTwoFactorTrustedDeviceStore(),
        secretProtector: const PlaintextAuthTwoFactorSecretProtector(),
      );
      final enrollment = await feature.beginEnrollment('callback-user');
      await feature.verifyEnrollment(
        'callback-user',
        generateAuthTotpCode(enrollment.secret),
      );
      AuthProvider? completedProvider;
      AuthCredentials? completedCredentials;
      final manager = AuthManager(
        AuthOptions<EngineContext>(
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          providers: [
            CredentialsProvider(
              id: 'first-credentials',
              authorize: (_, _, _) async => null,
            ),
            CredentialsProvider(
              id: 'callback-credentials',
              authorize: (_, _, credentials) async =>
                  AuthUser(id: 'callback-user', email: credentials.email),
            ),
          ],
          features: [feature],
          callbacks: AuthCallbacks<EngineContext>(
            signIn: (context) {
              completedProvider = context.provider;
              completedCredentials = context.credentials;
              return const AuthSignInResult.allow();
            },
          ),
        ),
      );
      final engine = _authEngine(manager);
      await engine.initialize();
      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);

      final csrfResponse = await client.get('/auth/csrf');
      final csrf = csrfResponse.json()['csrfToken'] as String;
      final csrfCookie = csrfResponse.cookie('test_session')!;
      final challenged = await client.postJson(
        '/auth/signin/callback-credentials',
        {
          'email': 'callback@example.com',
          'password': 'callback-password',
          'username': 'callback-user',
          'tenant': 'alpha',
          '_csrf': csrf,
        },
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(csrfCookie)],
        },
      );
      challenged.assertStatus(HttpStatus.accepted);

      final completed = await client.postJson(
        '/auth/2fa/challenge/verify',
        {
          'challengeToken': challenged.json()['challengeToken'],
          'code': generateAuthTotpCode(enrollment.secret),
          '_csrf': csrf,
        },
        headers: {
          HttpHeaders.cookieHeader: [_cookieHeader(csrfCookie)],
        },
      );

      completed.assertStatus(HttpStatus.ok);
      expect(completed.json()['user']['id'], equals('callback-user'));
      expect(completedProvider?.id, equals('callback-credentials'));
      expect(completedCredentials?.email, equals('callback@example.com'));
      expect(completedCredentials?.username, equals('callback-user'));
      expect(completedCredentials?.attributes['tenant'], equals('alpha'));
      expect(completedCredentials?.password, isNull);
    },
  );

  test('TOTP enrollment and one-time recovery code flow', () async {
    final store = InMemoryAuthStore();
    final factorStore = InMemoryAuthTwoFactorStore();
    final challengeStore = InMemoryAuthTwoFactorChallengeStore();
    final stepUpStore = InMemoryAuthTwoFactorStepUpStore();
    final feature = TwoFactorFeature<EngineContext>(
      store: factorStore,
      challengeStore: challengeStore,
      pendingRecoveryStore: InMemoryAuthTwoFactorPendingRecoveryStore(
        factorStore: factorStore,
        challengeStore: challengeStore,
      ),
      trustedDeviceStore: InMemoryAuthTwoFactorTrustedDeviceStore(),
      stepUpStore: stepUpStore,
      secretProtector: const PlaintextAuthTwoFactorSecretProtector(),
    );
    final manager = AuthManager(
      AuthOptions<EngineContext>(
        store: store,
        storeMode: AuthStoreMode.ephemeral,
        providers: [CredentialsProvider()],
        passwordHasher: _testHasher(),
        features: [feature],
      ),
    );
    await authorizeCredentialsRegistration(
      store: store,
      passwordHasher: manager.options.passwordHasher,
      provider: CredentialsProvider(),
      context: Object(),
      credentials: AuthCredentials(
        email: 'ada@example.com',
        password: 'correct horse battery staple',
      ),
    );
    final engine = _authEngine(manager);
    await engine.initialize();
    final client = TestClient(RoutedRequestHandler(engine));
    addTearDown(client.close);

    final csrfResponse = await client.get('/auth/csrf');
    final csrf = csrfResponse.json()['csrfToken'] as String;
    final csrfCookie = csrfResponse.cookie('test_session')!;
    final login = await client.postJson(
      '/auth/signin/credentials',
      {
        'email': 'ada@example.com',
        'password': 'correct horse battery staple',
        '_csrf': csrf,
      },
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(csrfCookie)],
      },
    );
    login.assertStatus(HttpStatus.ok);
    final authCookie = login.cookie('test_session')!;

    final enrollment = await client.postJson(
      '/auth/2fa/enroll',
      {'accountLabel': 'ada@example.com', '_csrf': csrf},
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(authCookie)],
      },
    );
    enrollment.assertStatus(HttpStatus.ok);
    final enrollmentJson = enrollment.json();
    final secret = enrollmentJson['secret'] as String;
    expect(enrollmentJson['otpauthUri'], startsWith('otpauth://totp/'));

    final code = generateAuthTotpCode(secret);
    final activated = await client.postJson(
      '/auth/2fa/enroll/verify',
      {'code': code, '_csrf': csrf},
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(authCookie)],
      },
    );
    activated.assertStatus(HttpStatus.ok);
    final recoveryCodes = activated.json()['recoveryCodes'] as List<dynamic>;
    expect(recoveryCodes, hasLength(10));

    final status = await client.get(
      '/auth/2fa/status',
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(authCookie)],
      },
    );
    status.assertStatus(HttpStatus.ok);
    expect(status.json()['enabled'], isTrue);
    expect(status.json()['recoveryCodesRemaining'], equals(10));

    final recovery = await client.postJson(
      '/auth/2fa/recovery-code',
      {'recoveryCode': recoveryCodes.first, '_csrf': csrf},
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(authCookie)],
      },
    );
    recovery.assertStatus(HttpStatus.ok);
    expect(recovery.json()['method'], equals('recovery_code'));

    final remaining = await client.get(
      '/auth/2fa/status',
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(authCookie)],
      },
    );
    expect(remaining.json()['recoveryCodesRemaining'], equals(9));

    final replay = await client.postJson(
      '/auth/2fa/recovery-code',
      {'recoveryCode': recoveryCodes.first, '_csrf': csrf},
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(authCookie)],
      },
    );
    replay.assertStatus(HttpStatus.unauthorized);
    expect(replay.json()['error'], equals('two_factor_invalid_recovery_code'));

    final signedOut = await client.postJson(
      '/auth/signout',
      {'_csrf': csrf},
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(authCookie)],
      },
    );
    signedOut.assertStatus(HttpStatus.ok);

    final recoveryChallenged = await client.postJson(
      '/auth/signin/credentials',
      {
        'email': 'ada@example.com',
        'password': 'correct horse battery staple',
        '_csrf': csrf,
      },
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(authCookie)],
      },
    );
    recoveryChallenged.assertStatus(HttpStatus.accepted);
    final recoveryCompleted = await client.postJson(
      '/auth/2fa/challenge/recovery-code',
      {
        'challengeToken': recoveryChallenged.json()['challengeToken'],
        'recoveryCode': recoveryCodes[1],
        '_csrf': csrf,
      },
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(authCookie)],
      },
    );
    recoveryCompleted.assertStatus(HttpStatus.ok);
    final recoverySessionCookie = recoveryCompleted.cookie('test_session')!;
    final recoverySignedOut = await client.postJson(
      '/auth/signout',
      {'_csrf': csrf},
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(recoverySessionCookie)],
      },
    );
    recoverySignedOut.assertStatus(HttpStatus.ok);

    final challenged = await client.postJson(
      '/auth/signin/credentials',
      {
        'email': 'ada@example.com',
        'password': 'correct horse battery staple',
        '_csrf': csrf,
      },
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(authCookie)],
      },
    );
    challenged.assertStatus(HttpStatus.accepted);
    expect(challenged.json()['status'], equals('two_factor_required'));
    final challengeToken = challenged.json()['challengeToken'] as String;

    final completed = await client.postJson(
      'https://server_testing.internal/auth/2fa/challenge/verify',
      {
        'challengeToken': challengeToken,
        'code': generateAuthTotpCode(secret),
        'trustDevice': true,
        '_csrf': csrf,
      },
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(authCookie)],
      },
    );
    completed.assertStatus(HttpStatus.ok);
    expect(completed.json()['user']['id'], isNotEmpty);
    final trustedCookie = completed.cookie('two_factor_trusted_device')!;
    expect(trustedCookie.secure, isTrue);
    final completedSessionCookie = completed.cookie('test_session')!;

    final completedSignOut = await client.postJson(
      '/auth/signout',
      {'_csrf': csrf},
      headers: {
        HttpHeaders.cookieHeader: [
          '${_cookieHeader(completedSessionCookie)}; '
              '${_cookieHeader(trustedCookie)}',
        ],
      },
    );
    completedSignOut.assertStatus(HttpStatus.ok);

    final trustedSignIn = await client.postJson(
      '/auth/signin/credentials',
      {
        'email': 'ada@example.com',
        'password': 'correct horse battery staple',
        '_csrf': csrf,
      },
      headers: {
        HttpHeaders.cookieHeader: [
          '${_cookieHeader(csrfCookie)}; ${_cookieHeader(trustedCookie)}',
        ],
      },
    );
    trustedSignIn.assertStatus(HttpStatus.ok);
    final trustedSessionCookie = trustedSignIn.cookie('test_session')!;

    final stepUp = await client.postJson(
      'https://server_testing.internal/auth/2fa/step-up',
      {'code': generateAuthTotpCode(secret), '_csrf': csrf},
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(trustedSessionCookie)],
      },
    );
    stepUp.assertStatus(HttpStatus.ok);
    expect(stepUp.json()['verified'], isTrue);
    expect(stepUp.cookie('two_factor_step_up')?.secure, isTrue);

    final stepUpRevoked = await client.postJson(
      '/auth/2fa/step-up/revoke',
      {'_csrf': csrf},
      headers: {
        HttpHeaders.cookieHeader: [
          '${_cookieHeader(trustedSessionCookie)}; '
              '${_cookieHeader(stepUp.cookie('two_factor_step_up')!)}',
        ],
      },
    );
    stepUpRevoked.assertStatus(HttpStatus.ok);
    expect(stepUpRevoked.json()['status'], equals('step_up_revoked'));

    final revoked = await client.postJson(
      '/auth/2fa/trusted-devices/revoke',
      {'_csrf': csrf},
      headers: {
        HttpHeaders.cookieHeader: [_cookieHeader(trustedSessionCookie)],
      },
    );
    revoked.assertStatus(HttpStatus.ok);
    expect(revoked.json()['status'], equals('trusted_devices_revoked'));
    expect(revoked.cookie('two_factor_trusted_device')?.value, isEmpty);
  });
}
