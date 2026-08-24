import 'dart:convert';

import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  group('two-factor atomic backend', () {
    test('serializes concurrent successful TOTP verification', () async {
      final fixture = await _enrolledFixture();

      await Future.wait<void>(<Future<void>>[
        for (var index = 0; index < 20; index++)
          fixture.plugin.verifyTotp(
            fixture.userId,
            fixture.code,
            now: fixture.now,
          ),
      ]);

      final factor = fixture.backend.factorStore.findByUserId(fixture.userId);
      expect(factor, isNotNull);
      expect(factor!.failedVerificationCount, 0);
      expect(factor.lockedUntil, isNull);
    });

    test(
      'serializes concurrent disable, regenerate, and recovery use',
      () async {
        final now = DateTime.utc(2030);
        for (final order in <List<String>>[
          <String>['disable', 'regenerate', 'recover'],
          <String>['regenerate', 'recover', 'disable'],
          <String>['recover', 'disable', 'regenerate'],
        ]) {
          final backend = InMemoryAuthTwoFactorBackend();
          final factor = _factor(
            'user-${order.first}',
            now,
            recoveryCodeHashes: const <String>['recovery-hash'],
          );
          backend.factorStore.save(factor);
          final operations =
              <String, Future<AuthTwoFactorCommandResult> Function()>{
                'disable': () => backend.disable(
                  AuthTwoFactorDisableCommand(
                    expected: factor,
                    valid: true,
                    policy: _policy(now),
                  ),
                ),
                'regenerate': () => backend.regenerateRecoveryCodes(
                  AuthTwoFactorRegenerateRecoveryCodesCommand(
                    expected: factor,
                    valid: true,
                    recoveryCodeHashes: const <String>['replacement-hash'],
                    policy: _policy(now),
                  ),
                ),
                'recover': () => backend.useRecoveryCode(
                  AuthTwoFactorUseRecoveryCodeCommand(
                    userId: factor.userId,
                    recoveryCodeHash: 'recovery-hash',
                    policy: _policy(now),
                  ),
                ),
              };

          final results = await Future.wait<AuthTwoFactorCommandResult>(
            <Future<AuthTwoFactorCommandResult>>[
              for (final id in order) operations[id]!(),
            ],
          );

          expect(
            results
                .where(
                  (result) =>
                      result.status == AuthTwoFactorCommandStatus.applied,
                )
                .length,
            1,
            reason: 'order $order must have one winning snapshot mutation',
          );
        }
      },
    );

    test(
      'rejects stale pending challenges without consuming recovery',
      () async {
        final now = DateTime.utc(2030);
        final backend = InMemoryAuthTwoFactorBackend();
        const userId = 'stale-user';
        backend.factorStore.save(
          _factor(
            userId,
            now,
            recoveryCodeHashes: const <String>['recovery-hash'],
          ),
        );
        backend.challengeStore.create(
          AuthTwoFactorChallengeRecord(
            id: 'stale-id',
            tokenHash: 'stale-hash',
            userId: userId,
            createdAt: now,
            expiresAt: now.add(const Duration(seconds: 1)),
          ),
        );

        final result = await backend.completeRecoveryChallenge(
          AuthTwoFactorCompleteRecoveryChallengeCommand(
            tokenHash: 'stale-hash',
            recoveryCodeHash: 'recovery-hash',
            policy: _policy(now.add(const Duration(seconds: 1))),
          ),
        );

        expect(result.status, AuthTwoFactorCommandStatus.expired);
        expect(
          backend.factorStore.findByUserId(userId)!.recoveryCodeHashes,
          const <String>['recovery-hash'],
        );
      },
    );

    test('rolls back every disable write after an injected fault', () async {
      final now = DateTime.utc(2030);
      final faults = AuthTwoFactorFaultInjector();
      final backend = InMemoryAuthTwoFactorBackend(faultInjector: faults);
      const userId = 'rollback-user';
      final factor = _factor(userId, now);
      backend.factorStore.save(factor);
      backend.challengeStore.create(_challenge(userId, now));
      backend.trustedDeviceStore.create(_trusted(userId, now));
      backend.stepUpStore.create(_proof(userId, now));
      faults.failNext(AuthTwoFactorAtomicFaultPoint.afterChallengeWrite);

      await expectLater(
        backend.disable(
          AuthTwoFactorDisableCommand(
            expected: factor,
            valid: true,
            policy: _policy(now),
          ),
        ),
        throwsA(isA<AuthTwoFactorInjectedFault>()),
      );

      expect(backend.factorStore.findByUserId(userId), isNotNull);
      expect(
        backend.challengeStore.findByTokenHash('challenge-hash'),
        isNotNull,
      );
      expect(
        backend.trustedDeviceStore.findActive(userId, 'device-hash', now: now),
        isNotNull,
      );
      expect(
        backend.stepUpStore.findActive(
          userId,
          'session-hash',
          'proof-hash',
          now: now,
        ),
        isNotNull,
      );
    });

    test(
      'rolls back challenge consumption and trusted-device issuance together',
      () async {
        final now = DateTime.utc(2030);
        final faults = AuthTwoFactorFaultInjector();
        final backend = InMemoryAuthTwoFactorBackend(faultInjector: faults);
        final plugin = TwoFactorPlugin<Object>(
          backend: backend,
          secretProtector: const PlaintextAuthTwoFactorSecretProtector(),
          secretGenerator: _uniqueGenerator(),
        );
        final enrollment = await plugin.beginEnrollment(
          'challenge-user',
          now: now,
        );
        final code = generateAuthTotpCode(
          enrollment.secret,
          timestampSeconds: now.millisecondsSinceEpoch ~/ 1000,
        );
        await plugin.verifyEnrollment('challenge-user', code, now: now);
        final challenge = (await plugin.beginSignInChallenge(
          'challenge-user',
          now: now,
        ))!;
        faults.failNext(AuthTwoFactorAtomicFaultPoint.afterTrustedDeviceWrite);

        await expectLater(
          plugin.completeSignInChallenge(
            challenge.token,
            code,
            trustDevice: true,
            now: now,
          ),
          throwsA(isA<AuthTwoFactorInjectedFault>()),
        );

        final retry = await plugin.completeSignInChallenge(
          challenge.token,
          code,
          trustDevice: true,
          now: now,
        );
        expect(retry.userId, 'challenge-user');
        expect(retry.trustedDevice, isNotNull);
      },
    );

    test(
      'rolls back recovery digest and pending challenge consumption together',
      () async {
        final now = DateTime.utc(2030);
        final faults = AuthTwoFactorFaultInjector();
        final backend = InMemoryAuthTwoFactorBackend(faultInjector: faults);
        final plugin = TwoFactorPlugin<Object>(
          backend: backend,
          secretProtector: const PlaintextAuthTwoFactorSecretProtector(),
          secretGenerator: _uniqueGenerator(),
        );
        final enrollment = await plugin.beginEnrollment(
          'recovery-user',
          now: now,
        );
        final code = generateAuthTotpCode(
          enrollment.secret,
          timestampSeconds: now.millisecondsSinceEpoch ~/ 1000,
        );
        final recovery = await plugin.verifyEnrollment(
          'recovery-user',
          code,
          now: now,
        );
        final challenge = (await plugin.beginSignInChallenge(
          'recovery-user',
          now: now,
        ))!;
        faults.failNext(AuthTwoFactorAtomicFaultPoint.afterChallengeWrite);

        await expectLater(
          plugin.completeRecoverySignInChallenge(
            challenge.token,
            recovery.codes.first,
            now: now,
          ),
          throwsA(isA<AuthTwoFactorInjectedFault>()),
        );

        final retry = await plugin.completeRecoverySignInChallenge(
          challenge.token,
          recovery.codes.first,
          now: now,
        );
        expect(retry.userId, 'recovery-user');
        expect(
          (await plugin.status(
            'recovery-user',
            now: now,
          )).recoveryCodesRemaining,
          9,
        );
      },
    );

    test('binds step-up proof to the correct user and session', () async {
      final fixture = await _enrolledFixture();
      final proof = await fixture.plugin.verifyStepUp(
        fixture.userId,
        'session-a',
        fixture.code,
        now: fixture.now,
      );

      expect(
        await fixture.plugin.isStepUpValid(
          fixture.userId,
          'session-a',
          proof.token,
          now: fixture.now,
        ),
        isTrue,
      );
      expect(
        await fixture.plugin.isStepUpValid(
          'other-user',
          'session-a',
          proof.token,
          now: fixture.now,
        ),
        isFalse,
      );
      expect(
        await fixture.plugin.isStepUpValid(
          fixture.userId,
          'session-b',
          proof.token,
          now: fixture.now,
        ),
        isFalse,
      );
    });

    test(
      'replayed trusted device cannot cross users or survive revoke',
      () async {
        final fixture = await _enrolledFixture();
        final trusted = await fixture.plugin.issueTrustedDevice(
          fixture.userId,
          fixture.code,
          now: fixture.now,
        );
        final otherEnrollment = await fixture.plugin.beginEnrollment(
          'other-user',
          now: fixture.now,
        );
        await fixture.plugin.verifyEnrollment(
          'other-user',
          generateAuthTotpCode(
            otherEnrollment.secret,
            timestampSeconds: fixture.now.millisecondsSinceEpoch ~/ 1000,
          ),
          now: fixture.now,
        );

        expect(
          await fixture.plugin.beginSignInChallenge(
            fixture.userId,
            trustedDeviceToken: trusted.token,
            now: fixture.now,
          ),
          isNull,
        );
        expect(
          await fixture.plugin.beginSignInChallenge(
            'other-user',
            trustedDeviceToken: trusted.token,
            now: fixture.now,
          ),
          isNotNull,
        );

        await fixture.plugin.revokeAllTrustedDevices(
          fixture.userId,
          now: fixture.now,
        );
        expect(
          await fixture.plugin.beginSignInChallenge(
            fixture.userId,
            trustedDeviceToken: trusted.token,
            now: fixture.now,
          ),
          isNotNull,
        );
      },
    );

    test(
      'public serialization excludes protected and hashed material',
      () async {
        final fixture = await _enrolledFixture();
        final factor = fixture.backend.factorStore.findByUserId(
          fixture.userId,
        )!;
        final trusted = await fixture.plugin.issueTrustedDevice(
          fixture.userId,
          fixture.code,
          now: fixture.now,
        );
        final proof = await fixture.plugin.verifyStepUp(
          fixture.userId,
          'raw-session-binding',
          fixture.code,
          now: fixture.now,
        );
        final serialized = jsonEncode(<String, Object?>{
          'status': (await fixture.plugin.status(fixture.userId)).toJson(),
          'proof': proof.toJson(),
        });

        expect(serialized, isNot(contains(factor.protectedSecret)));
        for (final digest in factor.recoveryCodeHashes) {
          expect(serialized, isNot(contains(digest)));
        }
        expect(serialized, isNot(contains(trusted.token)));
        expect(serialized, isNot(contains(proof.token)));
        expect(serialized, isNot(contains('raw-session-binding')));
      },
    );
  });
}

final class _Fixture {
  const _Fixture({
    required this.userId,
    required this.now,
    required this.code,
    required this.backend,
    required this.plugin,
  });

  final String userId;
  final DateTime now;
  final String code;
  final InMemoryAuthTwoFactorBackend backend;
  final TwoFactorPlugin<Object> plugin;
}

Future<_Fixture> _enrolledFixture({String userId = 'user-1'}) async {
  final now = DateTime.utc(2030);
  final backend = InMemoryAuthTwoFactorBackend();
  final plugin = TwoFactorPlugin<Object>(
    backend: backend,
    secretProtector: const PlaintextAuthTwoFactorSecretProtector(),
    secretGenerator: _uniqueGenerator(),
  );
  final enrollment = await plugin.beginEnrollment(userId, now: now);
  final code = generateAuthTotpCode(
    enrollment.secret,
    timestampSeconds: now.millisecondsSinceEpoch ~/ 1000,
  );
  await plugin.verifyEnrollment(userId, code, now: now);
  return _Fixture(
    userId: userId,
    now: now,
    code: code,
    backend: backend,
    plugin: plugin,
  );
}

List<int> Function(int length) _uniqueGenerator() {
  var sequence = 0;
  return (length) {
    final current = sequence++;
    return List<int>.generate(
      length,
      (index) => (current * 31 + index + 1) & 0xff,
    );
  };
}

AuthTwoFactorAttemptPolicy _policy(DateTime now) => AuthTwoFactorAttemptPolicy(
  now: now,
  maxAttempts: 3,
  lockoutDuration: const Duration(minutes: 5),
);

AuthTwoFactorRecord _factor(
  String userId,
  DateTime now, {
  List<String> recoveryCodeHashes = const <String>[],
}) => AuthTwoFactorRecord(
  userId: userId,
  protectedSecret: 'protected-secret',
  enrollmentExpiresAt: now.add(const Duration(minutes: 10)),
  verified: true,
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

AuthTwoFactorTrustedDeviceRecord _trusted(String userId, DateTime now) =>
    AuthTwoFactorTrustedDeviceRecord(
      id: 'device-id',
      userId: userId,
      tokenHash: 'device-hash',
      createdAt: now,
      expiresAt: now.add(const Duration(days: 1)),
    );

AuthTwoFactorStepUpRecord _proof(String userId, DateTime now) =>
    AuthTwoFactorStepUpRecord(
      id: 'proof-id',
      userId: userId,
      sessionBindingHash: 'session-hash',
      tokenHash: 'proof-hash',
      createdAt: now,
      expiresAt: now.add(const Duration(minutes: 5)),
    );
