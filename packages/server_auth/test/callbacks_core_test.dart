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
}
