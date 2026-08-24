import 'dart:async';

import 'package:server_auth/src/core/two_factor.dart';

/// Creates an isolated two-factor backend for a conformance case.
typedef AuthTwoFactorBackendConformanceFactory =
    FutureOr<AuthTwoFactorBackend> Function();

/// Identifies a failed durable two-factor backend conformance case.
final class AuthTwoFactorBackendConformanceFailure implements Exception {
  /// Creates a failure for [caseId] caused by [cause].
  const AuthTwoFactorBackendConformanceFailure(this.caseId, this.cause);

  /// Stable identifier of the failed case.
  final String caseId;

  /// Error raised by the backend or the failed expectation.
  final Object cause;

  @override
  String toString() =>
      'AuthTwoFactorBackendConformanceFailure($caseId): $cause';
}

/// Verifies the required atomic command behavior of a two-factor backend.
///
/// Each case receives a fresh backend. Durable adapters should run this from
/// their own test suites against the real database implementation. The suite
/// covers command contention and cross-record outcomes; adapters must also use
/// their database's fault tooling to prove crash rollback.
Future<void> verifyAuthTwoFactorBackendConformance(
  AuthTwoFactorBackendConformanceFactory createBackend,
) async {
  await _case('concurrent_enrollment_verification', () async {
    final backend = await createBackend();
    final now = DateTime.utc(2030);
    final pending = _factor('conformance-enroll', now, verified: false);
    await backend.factorStore.save(pending);
    final command = AuthTwoFactorVerifyEnrollmentCommand(
      expected: pending,
      valid: true,
      recoveryCodeHashes: const <String>['recovery-hash'],
      policy: _policy(now),
    );
    final results = await Future.wait(<Future<AuthTwoFactorCommandResult>>[
      Future.sync(() => backend.verifyEnrollment(command)),
      Future.sync(() => backend.verifyEnrollment(command)),
    ]);
    _require(
      results
              .where(
                (result) => result.status == AuthTwoFactorCommandStatus.applied,
              )
              .length ==
          1,
      'exactly one enrollment verification must commit',
    );
  });

  await _case('recovery_code_single_use', () async {
    final backend = await createBackend();
    final now = DateTime.utc(2030);
    await backend.factorStore.save(
      _factor(
        'conformance-recovery',
        now,
        recoveryCodeHashes: const <String>['recovery-hash'],
      ),
    );
    final command = AuthTwoFactorUseRecoveryCodeCommand(
      userId: 'conformance-recovery',
      recoveryCodeHash: 'recovery-hash',
      policy: _policy(now),
    );
    final results = await Future.wait(<Future<AuthTwoFactorCommandResult>>[
      Future.sync(() => backend.useRecoveryCode(command)),
      Future.sync(() => backend.useRecoveryCode(command)),
    ]);
    _require(
      results
              .where(
                (result) => result.status == AuthTwoFactorCommandStatus.applied,
              )
              .length ==
          1,
      'one recovery digest must be consumed at most once',
    );
  });

  await _case('pending_recovery_completion', () async {
    final backend = await createBackend();
    final now = DateTime.utc(2030);
    const userId = 'conformance-pending-recovery';
    await backend.factorStore.save(
      _factor(userId, now, recoveryCodeHashes: const <String>['recovery-hash']),
    );
    await backend.challengeStore.create(_challenge(userId, now));
    final command = AuthTwoFactorCompleteRecoveryChallengeCommand(
      tokenHash: 'challenge-hash',
      recoveryCodeHash: 'recovery-hash',
      policy: _policy(now),
    );
    final first = await backend.completeRecoveryChallenge(command);
    final second = await backend.completeRecoveryChallenge(command);
    _require(
      first.status == AuthTwoFactorCommandStatus.applied,
      'first completion failed',
    );
    _require(
      second.status != AuthTwoFactorCommandStatus.applied,
      'challenge or code replay succeeded',
    );
    final factor = await backend.factorStore.findByUserId(userId);
    _require(
      factor != null && factor.recoveryCodeHashes.isEmpty,
      'recovery digest was not consumed',
    );
  });

  await _case('disable_clears_related_state', () async {
    final backend = await createBackend();
    final now = DateTime.utc(2030);
    const userId = 'conformance-disable';
    final factor = _factor(userId, now);
    await backend.factorStore.save(factor);
    await backend.challengeStore.create(_challenge(userId, now));
    await backend.trustedDeviceStore.create(
      AuthTwoFactorTrustedDeviceRecord(
        id: 'device-id',
        userId: userId,
        tokenHash: 'device-hash',
        createdAt: now,
        expiresAt: now.add(const Duration(days: 1)),
      ),
    );
    await backend.stepUpStore.create(
      AuthTwoFactorStepUpRecord(
        id: 'proof-id',
        userId: userId,
        sessionBindingHash: 'session-hash',
        tokenHash: 'proof-hash',
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 5)),
      ),
    );
    final result = await backend.disable(
      AuthTwoFactorDisableCommand(
        expected: factor,
        valid: true,
        policy: _policy(now),
      ),
    );
    _require(
      result.status == AuthTwoFactorCommandStatus.applied,
      'disable did not commit',
    );
    _require(
      await backend.factorStore.findByUserId(userId) == null,
      'factor survived disable',
    );
    _require(
      await backend.challengeStore.findByTokenHash('challenge-hash') == null,
      'challenge survived disable',
    );
    _require(
      await backend.trustedDeviceStore.findActive(
            userId,
            'device-hash',
            now: now,
          ) ==
          null,
      'trusted device survived disable',
    );
    _require(
      await backend.stepUpStore.findActive(
            userId,
            'session-hash',
            'proof-hash',
            now: now,
          ) ==
          null,
      'step-up proof survived disable',
    );
  });

  await _case('session_binding_and_user_isolation', () async {
    final backend = await createBackend();
    final now = DateTime.utc(2030);
    await backend.stepUpStore.create(
      AuthTwoFactorStepUpRecord(
        id: 'proof-id',
        userId: 'conformance-user-a',
        sessionBindingHash: 'session-a',
        tokenHash: 'proof-hash',
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 5)),
      ),
    );
    _require(
      await backend.stepUpStore.findActive(
            'conformance-user-b',
            'session-a',
            'proof-hash',
            now: now,
          ) ==
          null,
      'proof crossed user boundary',
    );
    _require(
      await backend.stepUpStore.findActive(
            'conformance-user-a',
            'session-b',
            'proof-hash',
            now: now,
          ) ==
          null,
      'proof crossed session boundary',
    );
  });
}

Future<void> _case(String id, Future<void> Function() body) async {
  try {
    await body();
  } on AuthTwoFactorBackendConformanceFailure {
    rethrow;
  } catch (error) {
    throw AuthTwoFactorBackendConformanceFailure(id, error);
  }
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

AuthTwoFactorAttemptPolicy _policy(DateTime now) => AuthTwoFactorAttemptPolicy(
  now: now,
  maxAttempts: 3,
  lockoutDuration: const Duration(minutes: 5),
);

AuthTwoFactorRecord _factor(
  String userId,
  DateTime now, {
  bool verified = true,
  List<String> recoveryCodeHashes = const <String>[],
}) => AuthTwoFactorRecord(
  userId: userId,
  protectedSecret: 'protected-secret',
  enrollmentExpiresAt: now.add(const Duration(minutes: 10)),
  verified: verified,
  recoveryCodeHashes: recoveryCodeHashes,
  updatedAt: now,
);

AuthTwoFactorChallengeRecord _challenge(String userId, DateTime now) =>
    AuthTwoFactorChallengeRecord(
      id: 'challenge-id',
      tokenHash: 'challenge-hash',
      userId: userId,
      createdAt: now,
      expiresAt: now.add(const Duration(minutes: 5)),
    );
