import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('AuthCallbacks isEmpty reflects configured handlers', () {
    const empty = AuthCallbacks<String>();
    final configured = AuthCallbacks<String>(
      signIn: (context) => const AuthSignInResult.allow(),
    );

    expect(empty.isEmpty, isTrue);
    expect(configured.isEmpty, isFalse);
  });

  test('AuthSignInResult constructors set expected values', () {
    const allow = AuthSignInResult.allow(redirectUrl: '/home');
    const deny = AuthSignInResult.deny();

    expect(allow.allowed, isTrue);
    expect(allow.redirectUrl, equals('/home'));
    expect(deny.allowed, isFalse);
    expect(deny.redirectUrl, isNull);
  });

  test('callback contexts preserve payloads and metadata', () {
    final user = AuthUser(id: 'user-1', email: 'user@example.com');
    final provider = CredentialsProvider();

    final signIn = AuthSignInCallbackContext<String>(
      context: 'ctx',
      user: user,
      strategy: AuthSessionStrategy.session,
      provider: provider,
      isNewUser: true,
      callbackUrl: '/dashboard',
    );
    final redirect = AuthRedirectCallbackContext<String>(
      context: 'ctx',
      url: '/login',
      baseUrl: 'https://example.test',
      provider: provider,
    );
    final jwt = AuthJwtCallbackContext<String>(
      context: 'ctx',
      token: {'sub': user.id},
      user: user,
      strategy: AuthSessionStrategy.jwt,
      provider: provider,
      isNewUser: true,
    );
    final session = AuthSessionCallbackContext<String>(
      context: 'ctx',
      session: AuthSession(
        user: user,
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
        strategy: AuthSessionStrategy.session,
      ),
      payload: {'user': user.id},
      user: user,
      strategy: AuthSessionStrategy.session,
      provider: provider,
    );

    expect(signIn.context, equals('ctx'));
    expect(signIn.user.id, equals(user.id));
    expect(signIn.isNewUser, isTrue);
    expect(signIn.callbackUrl, equals('/dashboard'));
    expect(redirect.url, equals('/login'));
    expect(redirect.baseUrl, equals('https://example.test'));
    expect(jwt.token['sub'], equals(user.id));
    expect(jwt.strategy, equals(AuthSessionStrategy.jwt));
    expect(session.payload['user'], equals(user.id));
    expect(session.strategy, equals(AuthSessionStrategy.session));
  });

  test(
    'resolveAuthSignInDecision defaults to allow when callback is absent',
    () async {
      final result = await resolveAuthSignInDecision<String>(
        callback: null,
        context: AuthSignInCallbackContext<String>(
          context: 'ctx',
          user: AuthUser(id: 'u1'),
          strategy: AuthSessionStrategy.session,
        ),
      );

      expect(result.allowed, isTrue);
    },
  );

  test(
    'resolveAuthSignInRedirectOrThrow returns callback redirect when allowed',
    () async {
      final redirect = await resolveAuthSignInRedirectOrThrow<String>(
        callback: (_) => const AuthSignInResult.allow(redirectUrl: '/home'),
        context: AuthSignInCallbackContext<String>(
          context: 'ctx',
          user: AuthUser(id: 'u1'),
          strategy: AuthSessionStrategy.session,
        ),
      );

      expect(redirect, equals('/home'));
    },
  );

  test(
    'resolveAuthSignInRedirectOrThrow throws when sign-in is denied',
    () async {
      await expectLater(
        resolveAuthSignInRedirectOrThrow<String>(
          callback: (_) => const AuthSignInResult.deny(),
          context: AuthSignInCallbackContext<String>(
            context: 'ctx',
            user: AuthUser(id: 'u1'),
            strategy: AuthSessionStrategy.session,
          ),
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'sign_in_blocked',
          ),
        ),
      );
    },
  );

  test(
    'resolveAuthSignInRedirectWithCallbacks forwards context and returns redirect',
    () async {
      final provider = CredentialsProvider();
      final credentials = AuthCredentials(email: 'u1@example.com');
      late AuthSignInCallbackContext<String> seen;

      final redirect = await resolveAuthSignInRedirectWithCallbacks<String>(
        callbacks: AuthCallbacks<String>(
          signIn: (context) {
            seen = context;
            return const AuthSignInResult.allow(redirectUrl: '/dashboard');
          },
        ),
        context: 'ctx',
        user: AuthUser(id: 'u1'),
        strategy: AuthSessionStrategy.jwt,
        provider: provider,
        credentials: credentials,
        isNewUser: true,
        callbackUrl: '/callback',
      );

      expect(redirect, equals('/dashboard'));
      expect(seen.context, equals('ctx'));
      expect(seen.user.id, equals('u1'));
      expect(seen.strategy, equals(AuthSessionStrategy.jwt));
      expect(seen.provider, same(provider));
      expect(seen.credentials, same(credentials));
      expect(seen.isNewUser, isTrue);
      expect(seen.callbackUrl, equals('/callback'));
    },
  );

  test(
    'resolveAuthSignInRedirectWithCallbacks throws when sign-in is denied',
    () async {
      await expectLater(
        resolveAuthSignInRedirectWithCallbacks<String>(
          callbacks: AuthCallbacks<String>(
            signIn: (_) => const AuthSignInResult.deny(),
          ),
          context: 'ctx',
          user: AuthUser(id: 'u1'),
          strategy: AuthSessionStrategy.session,
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'sign_in_blocked',
          ),
        ),
      );
    },
  );

  test(
    'resolveAuthSignInRedirectTarget uses sign-in redirect decision and resolver',
    () async {
      String? seenCandidate;
      final target = await resolveAuthSignInRedirectTarget<String>(
        callbacks: AuthCallbacks<String>(
          signIn: (_) =>
              const AuthSignInResult.allow(redirectUrl: '/from-signin'),
        ),
        context: 'ctx',
        user: AuthUser(id: 'u1'),
        strategy: AuthSessionStrategy.session,
        callbackUrl: '/fallback',
        resolveRedirect: (candidate) {
          seenCandidate = candidate;
          return '/resolved';
        },
      );

      expect(seenCandidate, equals('/from-signin'));
      expect(target, equals('/resolved'));
    },
  );

  test(
    'resolveAuthSignInRedirectTarget falls back to callbackUrl before resolver',
    () async {
      String? seenCandidate;
      final target = await resolveAuthSignInRedirectTarget<String>(
        callbacks: AuthCallbacks<String>(
          signIn: (_) => const AuthSignInResult.allow(),
        ),
        context: 'ctx',
        user: AuthUser(id: 'u1'),
        strategy: AuthSessionStrategy.session,
        callbackUrl: '/fallback',
        resolveRedirect: (candidate) {
          seenCandidate = candidate;
          return candidate;
        },
      );

      expect(seenCandidate, equals('/fallback'));
      expect(target, equals('/fallback'));
    },
  );

  test(
    'resolveAuthJwtClaims and resolveAuthSessionPayload pass through defaults',
    () async {
      final jwtContext = AuthJwtCallbackContext<String>(
        context: 'ctx',
        token: <String, dynamic>{'sub': 'u1'},
        user: AuthUser(id: 'u1'),
        strategy: AuthSessionStrategy.jwt,
      );
      final sessionContext = AuthSessionCallbackContext<String>(
        context: 'ctx',
        session: AuthSession(
          user: AuthUser(id: 'u1'),
          expiresAt: null,
          strategy: AuthSessionStrategy.session,
        ),
        payload: <String, dynamic>{'sub': 'u1'},
        user: AuthUser(id: 'u1'),
        strategy: AuthSessionStrategy.session,
      );

      final jwt = await resolveAuthJwtClaims<String>(
        callback: null,
        context: jwtContext,
      );
      final session = await resolveAuthSessionPayload<String>(
        callback: null,
        context: sessionContext,
      );

      expect(jwt, equals(<String, dynamic>{'sub': 'u1'}));
      expect(session, equals(<String, dynamic>{'sub': 'u1'}));
    },
  );

  test(
    'resolveAuthJwtClaimsWithCallbacks builds defaults and applies callback',
    () async {
      final user = AuthUser(id: 'u1', email: 'u1@example.com');

      final claims = await resolveAuthJwtClaimsWithCallbacks<String>(
        callbacks: AuthCallbacks<String>(
          jwt: (context) => <String, dynamic>{...context.token, 'plan': 'pro'},
        ),
        context: 'ctx',
        user: user,
        strategy: AuthSessionStrategy.jwt,
      );

      expect(claims['sub'], equals('u1'));
      expect(claims['plan'], equals('pro'));
    },
  );

  test(
    'resolveAuthSessionPayloadWithCallbacks builds defaults and applies callback',
    () async {
      final session = AuthSession(
        user: AuthUser(id: 'u1'),
        expiresAt: null,
        strategy: AuthSessionStrategy.session,
      );

      final payload = await resolveAuthSessionPayloadWithCallbacks<String>(
        callbacks: AuthCallbacks<String>(
          session: (context) => <String, dynamic>{
            ...context.payload,
            'note': 'custom',
          },
        ),
        context: 'ctx',
        session: session,
        strategy: AuthSessionStrategy.session,
      );

      expect(payload['user'], isA<Map<String, dynamic>>());
      expect(payload['note'], equals('custom'));
    },
  );

  test(
    'issueAuthJwtSessionWithCallbacks throws when secret is missing',
    () async {
      await expectLater(
        issueAuthJwtSessionWithCallbacks<String>(
          callbacks: const AuthCallbacks<String>(),
          context: 'ctx',
          options: const JwtSessionOptions(secret: ''),
          user: AuthUser(id: 'u1'),
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'missing_jwt_secret',
          ),
        ),
      );
    },
  );

  test(
    'issueAuthJwtSessionWithCallbacks issues token and session from callbacks',
    () async {
      final issued = await issueAuthJwtSessionWithCallbacks<String>(
        callbacks: AuthCallbacks<String>(
          jwt: (context) => <String, dynamic>{...context.token, 'plan': 'pro'},
        ),
        context: 'ctx',
        options: const JwtSessionOptions(secret: 'secret-test'),
        user: AuthUser(id: 'u1'),
      );

      expect(issued.claims['plan'], equals('pro'));
      expect(issued.issued.cookie.value, equals(issued.issued.token));
      expect(issued.session.token, equals(issued.issued.token));
      expect(issued.session.strategy, equals(AuthSessionStrategy.jwt));
    },
  );

  test(
    'resolveAuthSignInResultForStrategyWithCallbacks returns session strategy result',
    () async {
      final result =
          await resolveAuthSignInResultForStrategyWithCallbacks<String>(
            callbacks: const AuthCallbacks<String>(),
            context: 'ctx',
            strategy: AuthSessionStrategy.session,
            user: AuthUser(id: 'u1'),
            redirectUrl: '/dashboard',
            jwtOptions: const JwtSessionOptions(secret: 'unused'),
            sessionExpiresAt: DateTime.utc(2026, 2, 24, 12),
          );

      expect(result.issuedJwt, isNull);
      expect(result.result.redirectUrl, equals('/dashboard'));
      expect(
        result.result.session.strategy,
        equals(AuthSessionStrategy.session),
      );
      expect(
        result.result.session.expiresAt,
        equals(DateTime.utc(2026, 2, 24, 12)),
      );
    },
  );

  test(
    'resolveAuthSignInResultForStrategyWithCallbacks issues jwt strategy result',
    () async {
      final result =
          await resolveAuthSignInResultForStrategyWithCallbacks<String>(
            callbacks: const AuthCallbacks<String>(),
            context: 'ctx',
            strategy: AuthSessionStrategy.jwt,
            user: AuthUser(id: 'u1'),
            redirectUrl: '/dashboard',
            jwtOptions: const JwtSessionOptions(secret: 'secret-test'),
          );

      expect(result.issuedJwt, isNotNull);
      expect(result.result.redirectUrl, equals('/dashboard'));
      expect(result.result.session.strategy, equals(AuthSessionStrategy.jwt));
      expect(result.result.session.token, equals(result.issuedJwt!.token));
      expect(
        result.result.session.expiresAt,
        equals(result.issuedJwt!.expiresAt),
      );
    },
  );

  test(
    'resolveAuthRedirectTarget returns null when callback is absent',
    () async {
      final target = await resolveAuthRedirectTarget<String>(
        callback: null,
        context: AuthRedirectCallbackContext<String>(
          context: 'ctx',
          url: '/from',
          baseUrl: 'https://example.test',
        ),
      );

      expect(target, isNull);
    },
  );

  test(
    'resolveAuthRedirectTargetWithFallback returns fallback when callback is absent',
    () async {
      final target = await resolveAuthRedirectTargetWithFallback<String>(
        callback: null,
        context: AuthRedirectCallbackContext<String>(
          context: 'ctx',
          url: '/from',
          baseUrl: 'https://example.test',
        ),
        fallbackUrl: '/fallback',
      );

      expect(target, equals('/fallback'));
    },
  );

  test(
    'resolveAuthRedirectTargetWithFallback prefers callback result',
    () async {
      final target = await resolveAuthRedirectTargetWithFallback<String>(
        callback: (context) => '/resolved',
        context: AuthRedirectCallbackContext<String>(
          context: 'ctx',
          url: '/from',
          baseUrl: 'https://example.test',
        ),
        fallbackUrl: '/fallback',
      );

      expect(target, equals('/resolved'));
    },
  );

  test(
    'resolveAuthRedirectWithCallbacks returns null for missing redirect url',
    () async {
      final target = await resolveAuthRedirectWithCallbacks<String>(
        callbacks: const AuthCallbacks<String>(),
        context: 'ctx',
        url: null,
        baseUrl: 'https://example.test',
      );
      expect(target, isNull);
    },
  );

  test(
    'resolveAuthRedirectWithCallbacks falls back to provided url when callback is absent',
    () async {
      final target = await resolveAuthRedirectWithCallbacks<String>(
        callbacks: const AuthCallbacks<String>(),
        context: 'ctx',
        url: '/requested',
        baseUrl: 'https://example.test',
      );
      expect(target, equals('/requested'));
    },
  );

  test(
    'resolveAuthRedirectWithCallbacks prefers callback redirect result',
    () async {
      final target = await resolveAuthRedirectWithCallbacks<String>(
        callbacks: AuthCallbacks<String>(redirect: (context) => '/resolved'),
        context: 'ctx',
        url: '/requested',
        baseUrl: 'https://example.test',
      );
      expect(target, equals('/resolved'));
    },
  );
}
