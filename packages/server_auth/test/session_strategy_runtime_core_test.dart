import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test(
    'resolveAuthSessionUpdateForStrategyWithCallbacks updates session strategy',
    () async {
      final principal = AuthPrincipal(
        id: 'user-1',
        roles: const <String>['admin'],
        attributes: const <String, dynamic>{'email': 'user@example.com'},
      );
      final now = DateTime.utc(2026, 2, 24, 12);
      final expiresAt = DateTime.utc(2026, 2, 24, 18);

      var appliedMaxAge = 0;
      AuthPrincipal? persistedPrincipal;
      DateTime? issuedAt;
      final resolved =
          await resolveAuthSessionUpdateForStrategyWithCallbacks<String>(
            strategy: AuthSessionStrategy.session,
            callbacks: const AuthCallbacks<String>(),
            context: 'ctx',
            principal: principal,
            jwtOptions: const JwtSessionOptions(secret: 'unused'),
            applySessionMaxAge: () => appliedMaxAge += 1,
            persistSessionPrincipal: (value) => persistedPrincipal = value,
            writeSessionIssuedAt: (value) => issuedAt = value,
            resolveSessionExpiry: () => expiresAt,
            now: now,
          );

      expect(appliedMaxAge, equals(1));
      expect(persistedPrincipal?.id, equals('user-1'));
      expect(issuedAt, equals(now));
      expect(resolved.jwtCookie, isNull);
      expect(resolved.session.strategy, equals(AuthSessionStrategy.session));
      expect(resolved.session.user.id, equals('user-1'));
      expect(resolved.session.user.email, equals('user@example.com'));
      expect(resolved.session.expiresAt, equals(expiresAt));
    },
  );

  test(
    'resolveAuthSessionUpdateForStrategyWithCallbacks issues jwt cookie for jwt strategy',
    () async {
      final resolved =
          await resolveAuthSessionUpdateForStrategyWithCallbacks<String>(
            strategy: AuthSessionStrategy.jwt,
            callbacks: AuthCallbacks<String>(
              jwt: (context) => <String, dynamic>{
                ...context.token,
                'plan': 'pro',
              },
            ),
            context: 'ctx',
            principal: AuthPrincipal(id: 'user-1'),
            jwtOptions: const JwtSessionOptions(
              secret: 'secret-test',
              cookieName: 'jwt_cookie',
            ),
          );

      expect(resolved.session.strategy, equals(AuthSessionStrategy.jwt));
      expect(resolved.session.token, isNotEmpty);
      expect(resolved.jwtCookie, isNotNull);
      expect(resolved.jwtCookie!.name, equals('jwt_cookie'));
      expect(resolved.jwtCookie!.value, equals(resolved.session.token));

      final verifier = JwtVerifier(
        options: const JwtSessionOptions(
          secret: 'secret-test',
        ).toVerifierOptions(),
      );
      final payload = await verifier.verifyToken(resolved.session.token!);
      expect(payload.claims['plan'], equals('pro'));
    },
  );

  test(
    'resolveAuthSessionUpdateForStrategyWithCallbacks preserves missing_jwt_secret error',
    () async {
      await expectLater(
        resolveAuthSessionUpdateForStrategyWithCallbacks<String>(
          strategy: AuthSessionStrategy.jwt,
          callbacks: const AuthCallbacks<String>(),
          context: 'ctx',
          principal: AuthPrincipal(id: 'user-1'),
          jwtOptions: const JwtSessionOptions(secret: ''),
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
    'resolveAuthSessionForStrategyWithCallbacks returns null session when missing session principal',
    () async {
      var appliedMaxAge = 0;
      final resolved = await resolveAuthSessionForStrategyWithCallbacks<String>(
        strategy: AuthSessionStrategy.session,
        callbacks: const AuthCallbacks<String>(),
        context: 'ctx',
        jwtOptions: const JwtSessionOptions(secret: 'unused'),
        sessionUpdateAge: const Duration(minutes: 5),
        readSessionPrincipal: () => null,
        applySessionMaxAge: () => appliedMaxAge += 1,
      );

      expect(appliedMaxAge, equals(0));
      expect(resolved.session, isNull);
      expect(resolved.refreshCookie, isNull);
    },
  );

  test(
    'resolveAuthSessionForStrategyWithCallbacks refreshes session metadata when due',
    () async {
      final now = DateTime.utc(2026, 2, 24, 12);
      final principal = AuthPrincipal(id: 'user-1');
      final oldIssuedAt = serializeAuthSessionIssuedAt(
        now.subtract(const Duration(minutes: 10)),
      );
      final expiresAt = DateTime.utc(2026, 2, 24, 18);

      var appliedMaxAge = 0;
      var touched = 0;
      DateTime? writtenIssuedAt;
      final resolved = await resolveAuthSessionForStrategyWithCallbacks<String>(
        strategy: AuthSessionStrategy.session,
        callbacks: const AuthCallbacks<String>(),
        context: 'ctx',
        jwtOptions: const JwtSessionOptions(secret: 'unused'),
        sessionUpdateAge: const Duration(minutes: 5),
        readSessionPrincipal: () => principal,
        applySessionMaxAge: () => appliedMaxAge += 1,
        readSessionIssuedAt: () => oldIssuedAt,
        writeSessionIssuedAt: (value) => writtenIssuedAt = value,
        touchSession: () => touched += 1,
        resolveSessionExpiry: () => expiresAt,
        now: now,
      );

      expect(appliedMaxAge, equals(1));
      expect(touched, equals(1));
      expect(writtenIssuedAt, equals(now));
      expect(resolved.refreshCookie, isNull);
      expect(resolved.session, isNotNull);
      expect(resolved.session!.strategy, equals(AuthSessionStrategy.session));
      expect(resolved.session!.user.id, equals('user-1'));
      expect(resolved.session!.expiresAt, equals(expiresAt));
    },
  );

  test(
    'resolveAuthSessionForStrategyWithCallbacks refreshes jwt and returns refresh cookie',
    () async {
      const jwtOptions = JwtSessionOptions(
        secret: 'secret-test',
        cookieName: 'jwt_cookie',
      );
      final initial = issueAuthJwtToken(
        options: jwtOptions,
        claims: const <String, dynamic>{'sub': 'user-1'},
      );

      final resolved = await resolveAuthSessionForStrategyWithCallbacks<String>(
        strategy: AuthSessionStrategy.jwt,
        callbacks: AuthCallbacks<String>(
          jwt: (context) => <String, dynamic>{...context.token, 'plan': 'pro'},
        ),
        context: 'ctx',
        jwtOptions: jwtOptions,
        sessionUpdateAge: Duration.zero,
        readJwtToken: () => initial.token,
      );

      expect(resolved.session, isNotNull);
      expect(resolved.session!.strategy, equals(AuthSessionStrategy.jwt));
      expect(resolved.session!.user.id, equals('user-1'));
      expect(resolved.refreshCookie, isNotNull);
      expect(resolved.refreshCookie!.name, equals('jwt_cookie'));
      expect(resolved.refreshCookie!.value, equals(resolved.session!.token));

      final verifier = JwtVerifier(options: jwtOptions.toVerifierOptions());
      final payload = await verifier.verifyToken(resolved.session!.token!);
      expect(payload.claims['plan'], equals('pro'));
    },
  );

  test('resolveAuthSignOutForStrategy runs session logout hook', () async {
    var loggedOut = false;
    final resolved = await resolveAuthSignOutForStrategy(
      strategy: AuthSessionStrategy.session,
      jwtCookieName: 'jwt_cookie',
      logoutSession: () => loggedOut = true,
    );

    expect(loggedOut, isTrue);
    expect(resolved.expiredJwtCookie, isNull);
  });

  test('resolveAuthSignOutForStrategy builds expired jwt cookie', () async {
    final resolved = await resolveAuthSignOutForStrategy(
      strategy: AuthSessionStrategy.jwt,
      jwtCookieName: 'jwt_cookie',
    );

    expect(resolved.expiredJwtCookie, isNotNull);
    expect(resolved.expiredJwtCookie!.name, equals('jwt_cookie'));
    expect(resolved.expiredJwtCookie!.value, equals(''));
    expect(resolved.expiredJwtCookie!.maxAge, equals(0));
    expect(resolved.expiredJwtCookie!.path, equals('/'));
  });
}
