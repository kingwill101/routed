import 'package:routed_auth_cloudflare/routed_auth_cloudflare.dart';
import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

import 'support/fake_cloudflare_d1.dart';

const _secret = 'cloudflare-email-auth-backend-test-key';

void main() {
  test('D1 email backend passes public adapter conformance', () async {
    final databases = <FakeCloudflareD1Database>[];
    addTearDown(() {
      for (final database in databases) {
        database.close();
      }
    });
    await verifyAuthEmailBackendConformance(() async {
      final database = FakeCloudflareD1Database();
      databases.add(database);
      final store = await CloudflareD1AuthStore.open(database);
      return AuthEmailBackendConformanceFixture(
        magicLinks: store,
        emailOtps: store,
        users: store.users,
      );
    });
  });

  test('D1 magic-link consume rolls back the whole guarded batch', () async {
    final now = DateTime.utc(2030);
    for (var faultIndex = 0; faultIndex < 6; faultIndex++) {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      final store = await CloudflareD1AuthStore.open(
        database,
        clock: () => now,
      );
      await store.issueMagicLink(
        AuthMagicLinkIssueCommand(_magicRecord('rollback-token', now)),
      );
      database.failNextBatchAt = faultIndex;
      await expectLater(
        store.consumeMagicLink(_magicConsume('rollback-token', now)),
        throwsStateError,
        reason: 'batch statement $faultIndex did not fail',
      );
      expect(
        await store.users.findByEmail('d1-email@example.test'),
        isNull,
        reason: 'batch statement $faultIndex left a user behind',
      );
      expect(
        (await store.consumeMagicLink(
          _magicConsume('rollback-token', now),
        )).status,
        AuthMagicLinkConsumeStatus.consumed,
        reason: 'batch statement $faultIndex consumed the link on rollback',
      );
    }
  });

  test('D1 OTP sign-in rolls back attempt, consume, and user writes', () async {
    final now = DateTime.utc(2030);
    for (var faultIndex = 0; faultIndex < 6; faultIndex++) {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      final store = await CloudflareD1AuthStore.open(
        database,
        clock: () => now,
      );
      await store.issueEmailOtp(AuthEmailOtpIssueCommand(_otp('123456', now)));
      database.failNextBatchAt = faultIndex;
      await expectLater(
        store.signInWithEmailOtp(_signIn('123456', now)),
        throwsStateError,
        reason: 'batch statement $faultIndex did not fail',
      );
      expect(
        await store.users.findByEmail('d1-email@example.test'),
        isNull,
        reason: 'batch statement $faultIndex left a user behind',
      );
      expect(
        (await store.signInWithEmailOtp(_signIn('123456', now))).status,
        AuthEmailOtpUserTransitionStatus.applied,
        reason: 'batch statement $faultIndex consumed the OTP on rollback',
      );
    }
  });

  test('D1 persistence contains digests but no deliverable material', () async {
    final database = FakeCloudflareD1Database();
    addTearDown(database.close);
    final now = DateTime.utc(2030);
    const schema = CloudflareD1AuthSchema();
    final store = await CloudflareD1AuthStore.open(
      database,
      clock: () => now,
    );
    await store.issueMagicLink(
      AuthMagicLinkIssueCommand(_magicRecord('raw-magic-token', now)),
    );
    await store.issueEmailOtp(AuthEmailOtpIssueCommand(_otp('654321', now)));
    final magic = database
        .select('SELECT * FROM ${schema.table('magic_links')}')
        .single;
    final otp = database
        .select('SELECT * FROM ${schema.table('email_otps')}')
        .single;
    expect(magic.values, isNot(contains('raw-magic-token')));
    expect(otp.values, isNot(contains('654321')));
    expect(magic['token_hash'], hashOpaqueToken('raw-magic-token'));
    expect(
      otp['code_hash'],
      digestAuthEmailOtpCode(code: '654321', secret: _secret),
    );
  });
}

AuthMagicLinkRecord _magicRecord(String token, DateTime now) =>
    AuthMagicLinkRecord(
      providerId: 'email',
      email: 'd1-email@example.test',
      tokenHash: hashOpaqueToken(token),
      issuedAt: now,
      expiresAt: now.add(const Duration(minutes: 5)),
    );

AuthMagicLinkConsumeCommand _magicConsume(String token, DateTime now) =>
    AuthMagicLinkConsumeCommand(
      providerId: 'email',
      email: 'd1-email@example.test',
      tokenHash: hashOpaqueToken(token),
      now: now,
      candidate: AuthUser(id: 'd1-email-user', email: 'd1-email@example.test'),
    );

AuthEmailOtp _otp(String code, DateTime now) => AuthEmailOtp(
  id: 'd1-email-otp',
  email: 'd1-email@example.test',
  codeHash: digestAuthEmailOtpCode(code: code, secret: _secret),
  type: AuthEmailOtpType.signIn,
  createdAt: now,
  expiresAt: now.add(const Duration(minutes: 5)),
  maxAttempts: 3,
);

AuthEmailOtpSignInCommand _signIn(String code, DateTime now) =>
    AuthEmailOtpSignInCommand(
      email: 'd1-email@example.test',
      codeHash: digestAuthEmailOtpCode(code: code, secret: _secret),
      now: now,
      candidate: AuthUser(id: 'd1-email-user', email: 'd1-email@example.test'),
      disableSignUp: false,
    );
