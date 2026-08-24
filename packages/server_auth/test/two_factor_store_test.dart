import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2030);

  test('pending two-factor challenges are bounded and expire on access', () {
    final store = InMemoryAuthTwoFactorChallengeStore(
      clock: () => now,
      maxEntries: 2,
    );

    store.create(
      AuthTwoFactorChallengeRecord(
        id: 'challenge-1',
        tokenHash: 'hash-1',
        userId: 'user-1',
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 5)),
      ),
    );
    store.create(
      AuthTwoFactorChallengeRecord(
        id: 'challenge-2',
        tokenHash: 'hash-2',
        userId: 'user-2',
        createdAt: now.add(const Duration(seconds: 1)),
        expiresAt: now.add(const Duration(minutes: 5)),
      ),
    );
    store.create(
      AuthTwoFactorChallengeRecord(
        id: 'challenge-3',
        tokenHash: 'hash-3',
        userId: 'user-3',
        createdAt: now.add(const Duration(seconds: 2)),
        expiresAt: now.add(const Duration(minutes: 5)),
      ),
    );

    expect(store.findByTokenHash('hash-1'), isNull);
    expect(store.findByTokenHash('hash-2'), isNotNull);
    expect(store.findByTokenHash('hash-3'), isNotNull);
  });

  test('trusted-device records remove expired entries before eviction', () {
    var current = now;
    final store = InMemoryAuthTwoFactorTrustedDeviceStore(
      clock: () => current,
      maxEntries: 1,
    );

    store.create(
      AuthTwoFactorTrustedDeviceRecord(
        id: 'device-expired',
        userId: 'user-1',
        tokenHash: 'device-hash-1',
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 1)),
      ),
    );
    current = now.add(const Duration(minutes: 1));
    store.create(
      AuthTwoFactorTrustedDeviceRecord(
        id: 'device-fresh',
        userId: 'user-1',
        tokenHash: 'device-hash-2',
        createdAt: current,
        expiresAt: current.add(const Duration(minutes: 1)),
      ),
    );

    expect(store.findActive('user-1', 'device-hash-1', now: current), isNull);
    expect(
      store.findActive('user-1', 'device-hash-2', now: current),
      isNotNull,
    );
  });

  test('step-up proofs are bounded and expired proofs are pruned', () {
    var current = now;
    final store = InMemoryAuthTwoFactorStepUpStore(
      clock: () => current,
      maxEntries: 1,
    );

    store.create(
      AuthTwoFactorStepUpRecord(
        id: 'proof-expired',
        userId: 'user-1',
        sessionBindingHash: 'session-hash',
        tokenHash: 'proof-hash-1',
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 1)),
      ),
    );
    current = now.add(const Duration(minutes: 1));
    store.create(
      AuthTwoFactorStepUpRecord(
        id: 'proof-fresh',
        userId: 'user-1',
        sessionBindingHash: 'session-hash',
        tokenHash: 'proof-hash-2',
        createdAt: current,
        expiresAt: current.add(const Duration(minutes: 1)),
      ),
    );

    expect(
      store.findActive('user-1', 'session-hash', 'proof-hash-1', now: current),
      isNull,
    );
    expect(
      store.findActive('user-1', 'session-hash', 'proof-hash-2', now: current),
      isNotNull,
    );
  });

  test('recovery-code consumption enforces lockout atomically', () {
    final store = InMemoryAuthTwoFactorStore();
    final now = DateTime.utc(2030);
    final codeHash = hashOpaqueToken('RECOVERY-CODE');
    store.save(
      AuthTwoFactorRecord(
        userId: 'user-1',
        protectedSecret: 'protected-secret',
        enrollmentExpiresAt: now.add(const Duration(hours: 1)),
        verified: true,
        recoveryCodeHashes: [codeHash],
        lockedUntil: now.add(const Duration(minutes: 5)),
      ),
    );

    expect(store.consumeRecoveryCode('user-1', codeHash, now: now), isFalse);
    expect(store.findByUserId('user-1')!.recoveryCodeHashes, [codeHash]);
  });
}
