import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

const _secret = 'email-auth-backend-test-secret-key';

void main() {
  test('in-memory backend passes public durable-adapter conformance', () async {
    await verifyAuthEmailBackendConformance(() {
      final store = InMemoryAuthStore();
      return AuthEmailBackendConformanceFixture(
        magicLinks: store,
        emailOtps: store,
        users: store.users,
      );
    });
  });

  group('in-memory email transaction rollback', () {
    test('magic-link issuance rollback leaves no credential', () async {
      final faults = AuthEmailBackendFaultInjector()
        ..failNext(AuthEmailBackendFaultPoint.afterMagicLinkWrite);
      final store = InMemoryAuthStore(emailBackendFaultInjector: faults);
      final now = DateTime.utc(2030, 1, 1);
      await expectLater(
        store.issueMagicLink(
          AuthMagicLinkIssueCommand(_magicRecord('token-1', now)),
        ),
        throwsA(isA<AuthEmailBackendInjectedFault>()),
      );
      expect(
        (await store.consumeMagicLink(_magicConsume('token-1', now))).status,
        AuthMagicLinkConsumeStatus.invalid,
      );
    });

    test('magic-link consume rollback restores credential and user', () async {
      final faults = AuthEmailBackendFaultInjector();
      final store = InMemoryAuthStore(emailBackendFaultInjector: faults);
      final now = DateTime.utc(2030, 1, 1);
      await store.issueMagicLink(
        AuthMagicLinkIssueCommand(_magicRecord('token-2', now)),
      );
      faults.failNext(AuthEmailBackendFaultPoint.afterUserWrite);
      await expectLater(
        store.consumeMagicLink(_magicConsume('token-2', now)),
        throwsA(isA<AuthEmailBackendInjectedFault>()),
      );
      expect(await store.users.findByEmail('rollback@example.test'), isNull);
      expect(
        (await store.consumeMagicLink(_magicConsume('token-2', now))).status,
        AuthMagicLinkConsumeStatus.consumed,
      );
    });

    test('OTP issuance rollback leaves no credential', () async {
      final faults = AuthEmailBackendFaultInjector()
        ..failNext(AuthEmailBackendFaultPoint.afterEmailOtpWrite);
      final store = InMemoryAuthStore(emailBackendFaultInjector: faults);
      final now = DateTime.utc(2030, 1, 1);
      await expectLater(
        store.issueEmailOtp(AuthEmailOtpIssueCommand(_otp('123456', now))),
        throwsA(isA<AuthEmailBackendInjectedFault>()),
      );
      expect(
        (await store.verifyEmailOtp(_verify('123456', now))).status,
        AuthEmailOtpVerificationStatus.invalid,
      );
    });

    test(
      'OTP consume rollback restores attempts, credential, and user',
      () async {
        final faults = AuthEmailBackendFaultInjector();
        final store = InMemoryAuthStore(emailBackendFaultInjector: faults);
        final now = DateTime.utc(2030, 1, 1);
        await store.issueEmailOtp(
          AuthEmailOtpIssueCommand(_otp('654321', now)),
        );
        faults.failNext(AuthEmailBackendFaultPoint.afterUserWrite);
        await expectLater(
          store.signInWithEmailOtp(_signIn('654321', now)),
          throwsA(isA<AuthEmailBackendInjectedFault>()),
        );
        expect(await store.users.findByEmail('rollback@example.test'), isNull);
        expect(
          (await store.signInWithEmailOtp(_signIn('654321', now))).status,
          AuthEmailOtpUserTransitionStatus.applied,
        );
      },
    );
  });

  test(
    'email delivery failure is postcommit and does not restore a link',
    () async {
      final store = InMemoryAuthStore();
      final plugin = MagicLinkPlugin<Object>(
        tokenGenerator: () => 'delivery-token',
        sendMagicLink: (_) => throw StateError('delivery unavailable'),
      );
      final now = DateTime.utc(2030, 1, 1);
      await expectLater(
        startAuthEmailSignIn<Object>(
          backend: store,
          provider: plugin,
          context: Object(),
          email: 'rollback@example.test',
          callbackUrl: '/after',
          sessionStrategy: AuthSessionStrategy.session,
          now: now,
        ),
        throwsStateError,
      );
      expect(
        (await store.consumeMagicLink(
          _magicConsume('delivery-token', now),
        )).status,
        AuthMagicLinkConsumeStatus.consumed,
      );
    },
  );

  test('OTP delivery failure leaves the digest committed', () async {
    final store = InMemoryAuthStore();
    final plugin = EmailOtpPlugin<Object>(
      secret: _secret,
      generateOtp: (_) => '246810',
      sendCode: (_) => throw StateError('delivery unavailable'),
    );
    AuthRuntime<Object>(
      options: AuthOptions<Object>(
        store: store,
        storeMode: AuthStoreMode.ephemeral,
        providers: const [],
        plugins: [plugin],
      ),
    );
    final now = DateTime.utc(2030, 1, 1);

    await expectLater(
      plugin.sendVerificationOtp(
        context: Object(),
        email: 'rollback@example.test',
        type: AuthEmailOtpType.signIn,
        now: now,
      ),
      throwsStateError,
    );

    final verified = await store.verifyEmailOtp(_verify('246810', now));
    expect(verified.status, AuthEmailOtpVerificationStatus.verified);
  });
}

AuthMagicLinkRecord _magicRecord(String token, DateTime now) =>
    AuthMagicLinkRecord(
      providerId: 'email',
      email: 'rollback@example.test',
      tokenHash: hashOpaqueToken(token),
      issuedAt: now,
      expiresAt: now.add(const Duration(minutes: 5)),
    );

AuthMagicLinkConsumeCommand _magicConsume(String token, DateTime now) =>
    AuthMagicLinkConsumeCommand(
      providerId: 'email',
      email: 'rollback@example.test',
      tokenHash: hashOpaqueToken(token),
      now: now,
      candidate: AuthUser(id: 'rollback-user', email: 'rollback@example.test'),
    );

AuthEmailOtp _otp(String code, DateTime now) => AuthEmailOtp(
  id: 'rollback-otp',
  email: 'rollback@example.test',
  codeHash: digestAuthEmailOtpCode(code: code, secret: _secret),
  type: AuthEmailOtpType.signIn,
  createdAt: now,
  expiresAt: now.add(const Duration(minutes: 5)),
  maxAttempts: 3,
);

AuthEmailOtpVerifyCommand _verify(String code, DateTime now) =>
    AuthEmailOtpVerifyCommand(
      email: 'rollback@example.test',
      type: AuthEmailOtpType.signIn,
      codeHash: digestAuthEmailOtpCode(code: code, secret: _secret),
      now: now,
    );

AuthEmailOtpSignInCommand _signIn(String code, DateTime now) =>
    AuthEmailOtpSignInCommand(
      email: 'rollback@example.test',
      codeHash: digestAuthEmailOtpCode(code: code, secret: _secret),
      now: now,
      candidate: AuthUser(id: 'rollback-user', email: 'rollback@example.test'),
      disableSignUp: false,
    );
