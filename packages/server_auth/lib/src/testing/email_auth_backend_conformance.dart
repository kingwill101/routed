import 'dart:async';

import 'package:server_auth/src/core/email_auth_backend.dart';
import 'package:server_auth/src/core/email_otp_store.dart';
import 'package:server_auth/src/core/models.dart';
import 'package:server_auth/src/core/store.dart';
import 'package:server_auth/src/core/tokens.dart' show hashOpaqueToken;

/// Fresh adapter fixture used by each email-auth conformance case.
final class AuthEmailBackendConformanceFixture {
  /// Creates a fixture from the email capabilities and user store.
  const AuthEmailBackendConformanceFixture({
    required this.magicLinks,
    required this.emailOtps,
    required this.users,
  });

  /// Magic-link backend under test.
  final AuthMagicLinkBackend magicLinks;

  /// Email OTP backend under test.
  final AuthEmailOtpBackend emailOtps;

  /// User store shared by the backend capabilities.
  final AuthUserStore users;
}

/// Creates an isolated fixture for an email-auth conformance case.
typedef AuthEmailBackendConformanceFixtureFactory =
    FutureOr<AuthEmailBackendConformanceFixture> Function();

/// Describes a failed email-auth conformance case.
final class AuthEmailBackendConformanceFailure implements Exception {
  /// Creates a failure for [caseId] caused by [cause].
  const AuthEmailBackendConformanceFailure(this.caseId, this.cause);

  /// Stable identifier of the failed case.
  final String caseId;

  /// Error raised by the adapter or the failed expectation.
  final Object cause;

  @override
  String toString() => 'AuthEmailBackendConformanceFailure($caseId): $cause';
}

/// Verifies atomic one-time semantics required from durable email adapters.
///
/// The factory must return a fresh isolated database namespace per case.
/// Passing this suite does not replace adapter-specific commit-fault tests;
/// durable implementations must also prove that a failed database batch or
/// transaction leaves both credential and user state unchanged.
Future<void> verifyAuthEmailBackendConformance(
  AuthEmailBackendConformanceFixtureFactory createFixture,
) async {
  await _case('magic-link.concurrent-one-winner', () async {
    final fixture = await createFixture();
    final now = DateTime.utc(2030);
    await fixture.magicLinks.issueMagicLink(
      AuthMagicLinkIssueCommand(_magicRecord('magic-token', now: now)),
    );
    final results = await Future.wait([
      for (var index = 0; index < 16; index++)
        Future.sync(
          () => fixture.magicLinks.consumeMagicLink(
            _magicConsume(
              'magic-token',
              now: now,
              candidateId: 'magic-user-$index',
            ),
          ),
        ),
    ]);
    _check(
      results
              .where(
                (result) =>
                    result.status == AuthMagicLinkConsumeStatus.consumed,
              )
              .length ==
          1,
      'magic-link contention did not have exactly one winner',
    );
    _check(
      results.every(
        (result) =>
            result.status == AuthMagicLinkConsumeStatus.consumed ||
            result.status == AuthMagicLinkConsumeStatus.invalid,
      ),
      'magic-link contention returned an unexpected status',
    );
  });

  await _case('magic-link.provider-isolation', () async {
    final fixture = await createFixture();
    final now = DateTime.utc(2030);
    await fixture.magicLinks.issueMagicLink(
      AuthMagicLinkIssueCommand(_magicRecord('provider-a', now: now)),
    );
    await fixture.magicLinks.issueMagicLink(
      AuthMagicLinkIssueCommand(
        _magicRecord('provider-b', now: now, providerId: 'secondary'),
      ),
    );
    final first = await fixture.magicLinks.consumeMagicLink(
      _magicConsume('provider-a', now: now, candidateId: 'provider-a-user'),
    );
    final second = await fixture.magicLinks.consumeMagicLink(
      _magicConsume(
        'provider-b',
        now: now,
        providerId: 'secondary',
        candidateId: 'provider-b-user',
      ),
    );
    _check(
      first.status == AuthMagicLinkConsumeStatus.consumed &&
          second.status == AuthMagicLinkConsumeStatus.consumed,
      'one provider replaced another provider magic-link digest',
    );
  });

  await _case('email-otp.concurrent-one-winner', () async {
    final fixture = await createFixture();
    final now = DateTime.utc(2030);
    await fixture.emailOtps.issueEmailOtp(
      AuthEmailOtpIssueCommand(_otp('123456', now: now, maxAttempts: 32)),
    );
    final digest = _otpDigest('123456');
    final results = await Future.wait([
      for (var index = 0; index < 16; index++)
        Future.sync(
          () => fixture.emailOtps.verifyEmailOtp(
            AuthEmailOtpVerifyCommand(
              email: _email,
              type: AuthEmailOtpType.signIn,
              codeHash: digest,
              now: now,
            ),
          ),
        ),
    ]);
    _check(
      results
              .where(
                (result) =>
                    result.status == AuthEmailOtpVerificationStatus.verified,
              )
              .length ==
          1,
      'email OTP contention did not have exactly one winner',
    );
  });

  await _case('email-otp.attempt-lockout', () async {
    final fixture = await createFixture();
    final now = DateTime.utc(2030);
    await fixture.emailOtps.issueEmailOtp(
      AuthEmailOtpIssueCommand(_otp('123456', now: now, maxAttempts: 2)),
    );
    final first = await fixture.emailOtps.verifyEmailOtp(
      AuthEmailOtpVerifyCommand(
        email: _email,
        type: AuthEmailOtpType.signIn,
        codeHash: _otpDigest('000000'),
        now: now,
      ),
    );
    final second = await fixture.emailOtps.verifyEmailOtp(
      AuthEmailOtpVerifyCommand(
        email: _email,
        type: AuthEmailOtpType.signIn,
        codeHash: _otpDigest('000000'),
        now: now,
      ),
    );
    final validAfterLock = await fixture.emailOtps.verifyEmailOtp(
      AuthEmailOtpVerifyCommand(
        email: _email,
        type: AuthEmailOtpType.signIn,
        codeHash: _otpDigest('123456'),
        now: now,
      ),
    );
    _check(
      first.status == AuthEmailOtpVerificationStatus.invalid &&
          second.status == AuthEmailOtpVerificationStatus.tooManyAttempts &&
          validAfterLock.status ==
              AuthEmailOtpVerificationStatus.tooManyAttempts,
      'email OTP attempt accounting was not atomic and monotonic',
    );
  });

  await _case('email-otp.sign-in-user-transaction', () async {
    final fixture = await createFixture();
    final now = DateTime.utc(2030);
    await fixture.emailOtps.issueEmailOtp(
      AuthEmailOtpIssueCommand(_otp('654321', now: now, maxAttempts: 32)),
    );
    final results = await Future.wait([
      for (var index = 0; index < 16; index++)
        Future.sync(
          () => fixture.emailOtps.signInWithEmailOtp(
            AuthEmailOtpSignInCommand(
              email: _email,
              codeHash: _otpDigest('654321'),
              now: now,
              candidate: AuthUser(id: 'otp-user-$index', email: _email),
              disableSignUp: false,
            ),
          ),
        ),
    ]);
    final winners = results
        .where(
          (result) => result.status == AuthEmailOtpUserTransitionStatus.applied,
        )
        .toList(growable: false);
    _check(winners.length == 1, 'OTP sign-in had more than one winner');
    final user = await fixture.users.findByEmail(_email);
    _check(
      user != null && user.attributes['emailVerified'] == true,
      'OTP sign-in did not commit one verified user',
    );
  });

  await _case('email-otp.verify-user-binding', () async {
    final fixture = await createFixture();
    final now = DateTime.utc(2030);
    const userId = 'verify-user';
    await fixture.users.create(AuthUser(id: userId, email: _email));
    await fixture.emailOtps.issueEmailOtp(
      AuthEmailOtpIssueCommand(
        _otp('112233', now: now, type: AuthEmailOtpType.emailVerification),
      ),
    );
    final wrong = await fixture.emailOtps.verifyUserEmailWithOtp(
      AuthEmailOtpVerifyUserCommand(
        userId: 'another-user',
        email: _email,
        codeHash: _otpDigest('112233'),
        now: now,
      ),
    );
    _check(
      wrong.status != AuthEmailOtpUserTransitionStatus.applied,
      'email verification ignored the current-user binding',
    );
  });
}

const String _email = 'email-backend@example.test';
const String _secret = 'email-backend-conformance-secret-key';

AuthMagicLinkRecord _magicRecord(
  String rawToken, {
  required DateTime now,
  String providerId = 'email',
}) => AuthMagicLinkRecord(
  providerId: providerId,
  email: _email,
  tokenHash: hashOpaqueToken(rawToken),
  issuedAt: now,
  expiresAt: now.add(const Duration(minutes: 10)),
);

AuthMagicLinkConsumeCommand _magicConsume(
  String rawToken, {
  required DateTime now,
  required String candidateId,
  String providerId = 'email',
}) => AuthMagicLinkConsumeCommand(
  providerId: providerId,
  email: _email,
  tokenHash: hashOpaqueToken(rawToken),
  now: now,
  candidate: AuthUser(id: candidateId, email: _email),
);

AuthEmailOtp _otp(
  String code, {
  required DateTime now,
  AuthEmailOtpType type = AuthEmailOtpType.signIn,
  int maxAttempts = 3,
}) => AuthEmailOtp(
  id: 'otp-${type.name}-$code',
  email: _email,
  codeHash: _otpDigest(code),
  type: type,
  createdAt: now,
  expiresAt: now.add(const Duration(minutes: 5)),
  maxAttempts: maxAttempts,
);

String _otpDigest(String code) =>
    digestAuthEmailOtpCode(code: code, secret: _secret);

Future<void> _case(String id, Future<void> Function() body) async {
  try {
    await body();
  } on AuthEmailBackendConformanceFailure {
    rethrow;
  } catch (error) {
    throw AuthEmailBackendConformanceFailure(id, error);
  }
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}
