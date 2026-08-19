import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

TwoFactorPlugin<Object> _feature({
  int maxFailedVerificationAttempts = 5,
  Duration lockoutDuration = const Duration(minutes: 15),
  int period = 30,
}) {
  return TwoFactorPlugin<Object>(
    store: InMemoryAuthTwoFactorStore(),
    challengeStore: InMemoryAuthTwoFactorChallengeStore(),
    trustedDeviceStore: InMemoryAuthTwoFactorTrustedDeviceStore(),
    secretProtector: const PlaintextAuthTwoFactorSecretProtector(),
    maxFailedVerificationAttempts: maxFailedVerificationAttempts,
    lockoutDuration: lockoutDuration,
    period: period,
  );
}

final class _YieldingTwoFactorStore implements AuthTwoFactorStore {
  _YieldingTwoFactorStore(this.delegate);

  final InMemoryAuthTwoFactorStore delegate;

  Future<void> _yield() => Future<void>.delayed(Duration.zero);

  @override
  Future<AuthTwoFactorRecord?> findByUserId(String userId) async {
    await _yield();
    return delegate.findByUserId(userId);
  }

  @override
  Future<AuthTwoFactorRecord> save(AuthTwoFactorRecord record) async {
    await _yield();
    return delegate.save(record);
  }

  @override
  Future<bool> saveIfCurrent(
    AuthTwoFactorRecord expected,
    AuthTwoFactorRecord replacement,
  ) async {
    await _yield();
    return delegate.saveIfCurrent(expected, replacement);
  }

  @override
  Future<void> delete(String userId) async {
    await _yield();
    delegate.delete(userId);
  }

  @override
  Future<bool> consumeRecoveryCode(
    String userId,
    String codeHash, {
    required DateTime now,
  }) async {
    await _yield();
    return delegate.consumeRecoveryCode(userId, codeHash, now: now);
  }

  @override
  Future<AuthTwoFactorRecord?> recordFailedVerification(
    String userId, {
    required DateTime now,
    required int maxAttempts,
    required Duration lockoutDuration,
  }) async {
    await _yield();
    return delegate.recordFailedVerification(
      userId,
      now: now,
      maxAttempts: maxAttempts,
      lockoutDuration: lockoutDuration,
    );
  }

  @override
  Future<AuthTwoFactorRecord?> clearVerificationFailures(
    String userId, {
    required DateTime now,
  }) async {
    await _yield();
    return delegate.clearVerificationFailures(userId, now: now);
  }
}

Future<Object?> _captureRecoveryResult(
  Future<AuthTwoFactorRecoveryCodes> operation,
) async {
  try {
    return await operation;
  } catch (error) {
    return error;
  }
}

void main() {
  group('TOTP', () {
    test('matches RFC 6238 SHA-1 vectors', () {
      const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
      expect(
        generateAuthTotpCode(secret, timestampSeconds: 59, digits: 8),
        equals('94287082'),
      );
      expect(
        generateAuthTotpCode(secret, timestampSeconds: 1111111109, digits: 8),
        equals('07081804'),
      );
      expect(
        generateAuthTotpCode(secret, timestampSeconds: 1234567890, digits: 8),
        equals('89005924'),
      );
    });

    test('encodes generated secret bytes as unpadded base32', () {
      expect(encodeAuthBase32(<int>[0x66, 0x6f, 0x6f]), equals('MZXW6'));
    });

    test('rejects malformed padding, lengths, and trailing bits', () {
      expect(decodeAuthBase32('MZXW6==='), equals(<int>[0x66, 0x6f, 0x6f]));
      expect(decodeAuthBase32('M=ZXW6'), isNull);
      expect(decodeAuthBase32('MZXW6=Z'), isNull);
      expect(decodeAuthBase32('A'), isNull);
      expect(decodeAuthBase32('MZXW7'), isNull);
    });

    test('verifies configured non-default TOTP periods', () async {
      final now = DateTime.utc(2030, 1, 1);
      final feature = _feature(period: 60);
      final enrollment = await feature.beginEnrollment('user-1', now: now);
      final code = generateAuthTotpCode(
        enrollment.secret,
        timestampSeconds: now.millisecondsSinceEpoch ~/ 1000,
        period: 60,
      );
      await feature.verifyEnrollment('user-1', code, now: now);
      await feature.verifyTotp('user-1', code, now: now);
    });
  });

  group('TwoFactorPlugin', () {
    test(
      'atomically activates one enrollment under concurrent verification',
      () async {
        final now = DateTime.utc(2030, 1, 1);
        final feature = TwoFactorPlugin<Object>(
          store: _YieldingTwoFactorStore(InMemoryAuthTwoFactorStore()),
          challengeStore: InMemoryAuthTwoFactorChallengeStore(),
          trustedDeviceStore: InMemoryAuthTwoFactorTrustedDeviceStore(),
          secretProtector: const PlaintextAuthTwoFactorSecretProtector(),
        );
        final enrollment = await feature.beginEnrollment('user-1', now: now);
        final code = generateAuthTotpCode(
          enrollment.secret,
          timestampSeconds: now.millisecondsSinceEpoch ~/ 1000,
        );

        final results = await Future.wait([
          _captureRecoveryResult(
            feature.verifyEnrollment('user-1', code, now: now),
          ),
          _captureRecoveryResult(
            feature.verifyEnrollment('user-1', code, now: now),
          ),
        ]);

        expect(results.whereType<AuthTwoFactorRecoveryCodes>(), hasLength(1));
        expect(results.whereType<AuthFlowException>(), hasLength(1));
      },
    );

    test(
      'atomically replaces recovery codes under concurrent regeneration',
      () async {
        final now = DateTime.utc(2030, 1, 1);
        final feature = TwoFactorPlugin<Object>(
          store: _YieldingTwoFactorStore(InMemoryAuthTwoFactorStore()),
          challengeStore: InMemoryAuthTwoFactorChallengeStore(),
          trustedDeviceStore: InMemoryAuthTwoFactorTrustedDeviceStore(),
          secretProtector: const PlaintextAuthTwoFactorSecretProtector(),
        );
        final enrollment = await feature.beginEnrollment('user-1', now: now);
        final code = generateAuthTotpCode(
          enrollment.secret,
          timestampSeconds: now.millisecondsSinceEpoch ~/ 1000,
        );
        await feature.verifyEnrollment('user-1', code, now: now);

        final results = await Future.wait([
          _captureRecoveryResult(
            feature.regenerateRecoveryCodes('user-1', code, now: now),
          ),
          _captureRecoveryResult(
            feature.regenerateRecoveryCodes('user-1', code, now: now),
          ),
        ]);

        expect(results.whereType<AuthTwoFactorRecoveryCodes>(), hasLength(1));
        expect(results.whereType<AuthFlowException>(), hasLength(1));
      },
    );

    test('enrolls, activates, and consumes recovery codes once', () async {
      final generator = _queuedGenerator();
      final store = InMemoryAuthTwoFactorStore();
      final feature = TwoFactorPlugin<Object>(
        store: store,
        challengeStore: InMemoryAuthTwoFactorChallengeStore(),
        trustedDeviceStore: InMemoryAuthTwoFactorTrustedDeviceStore(),
        secretProtector: const PlaintextAuthTwoFactorSecretProtector(),
        secretGenerator: generator,
      );
      final now = DateTime.utc(2030, 1, 1);

      final enrollment = await feature.beginEnrollment(
        'user-1',
        accountLabel: 'ada@example.com',
        now: now,
      );
      expect(enrollment.secret, isNotEmpty);
      expect(enrollment.otpauthUri.scheme, equals('otpauth'));
      expect(enrollment.otpauthUri.host, equals('totp'));
      expect(
        generateAuthTotpCode(
          enrollment.secret,
          timestampSeconds: now.millisecondsSinceEpoch ~/ 1000,
        ),
        isNotEmpty,
      );

      final recovery = await feature.verifyEnrollment(
        'user-1',
        generateAuthTotpCode(
          enrollment.secret,
          timestampSeconds: now.millisecondsSinceEpoch ~/ 1000,
        ),
        now: now,
      );
      expect(recovery.codes, hasLength(10));
      expect(recovery.codes.toSet(), hasLength(10));
      expect((await feature.status('user-1', now: now)).enabled, isTrue);
      expect(
        (await feature.status('user-1', now: now)).recoveryCodesRemaining,
        equals(10),
      );

      await feature.useRecoveryCode('user-1', recovery.codes.first);
      expect(
        (await feature.status('user-1', now: now)).recoveryCodesRemaining,
        equals(9),
      );
      expect(
        () => feature.useRecoveryCode('user-1', recovery.codes.first),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            equals('two_factor_invalid_recovery_code'),
          ),
        ),
      );
    });

    test('direct recovery-code guesses share the account lockout', () async {
      final now = DateTime.utc(2030, 1, 1);
      final feature = _feature(
        maxFailedVerificationAttempts: 2,
        lockoutDuration: const Duration(minutes: 10),
      );
      final enrollment = await feature.beginEnrollment('user-1', now: now);
      await feature.verifyEnrollment(
        'user-1',
        generateAuthTotpCode(
          enrollment.secret,
          timestampSeconds: now.millisecondsSinceEpoch ~/ 1000,
        ),
        now: now,
      );

      for (var attempt = 0; attempt < 2; attempt++) {
        await expectLater(
          () => feature.useRecoveryCode(
            'user-1',
            'not-a-recovery-code',
            now: now,
          ),
          throwsA(
            isA<AuthFlowException>().having(
              (error) => error.code,
              'code',
              anyOf('two_factor_invalid_recovery_code', 'two_factor_locked'),
            ),
          ),
        );
      }

      await expectLater(
        () =>
            feature.useRecoveryCode('user-1', 'not-a-recovery-code', now: now),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'two_factor_locked',
          ),
        ),
      );
    });

    test('bounds a repeating recovery-code generator', () async {
      final now = DateTime.utc(2030, 1, 1);
      var calls = 0;
      final feature = TwoFactorPlugin<Object>(
        store: InMemoryAuthTwoFactorStore(),
        challengeStore: InMemoryAuthTwoFactorChallengeStore(),
        trustedDeviceStore: InMemoryAuthTwoFactorTrustedDeviceStore(),
        secretProtector: const PlaintextAuthTwoFactorSecretProtector(),
        secretGenerator: (length) {
          final current = calls++;
          return current == 0
              ? List<int>.generate(length, (index) => index + 1)
              : List<int>.filled(length, 7);
        },
      );
      final enrollment = await feature.beginEnrollment('user-1', now: now);

      await expectLater(
        () => feature.verifyEnrollment(
          'user-1',
          generateAuthTotpCode(
            enrollment.secret,
            timestampSeconds: now.millisecondsSinceEpoch ~/ 1000,
          ),
          now: now,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('could not produce unique codes'),
          ),
        ),
      );
    });

    test('locks repeated invalid TOTP attempts', () async {
      final generator = _queuedGenerator();
      final feature = TwoFactorPlugin<Object>(
        store: InMemoryAuthTwoFactorStore(),
        challengeStore: InMemoryAuthTwoFactorChallengeStore(),
        trustedDeviceStore: InMemoryAuthTwoFactorTrustedDeviceStore(),
        secretProtector: const PlaintextAuthTwoFactorSecretProtector(),
        secretGenerator: generator,
        maxFailedVerificationAttempts: 2,
        lockoutDuration: const Duration(minutes: 5),
      );
      final now = DateTime.utc(2030, 1, 1);
      final enrollment = await feature.beginEnrollment('user-1', now: now);
      await feature.verifyEnrollment(
        'user-1',
        generateAuthTotpCode(
          enrollment.secret,
          timestampSeconds: now.millisecondsSinceEpoch ~/ 1000,
        ),
        now: now,
      );

      for (var attempt = 0; attempt < 2; attempt++) {
        await expectLater(
          () => feature.verifyTotp('user-1', 'not-a-code', now: now),
          throwsA(isA<AuthFlowException>()),
        );
      }
      expect((await feature.status('user-1', now: now)).lockedUntil, isNotNull);
      expect(
        () => feature.verifyTotp('user-1', 'not-a-code', now: now),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            equals('two_factor_locked'),
          ),
        ),
      );
    });

    test('creates a single-use pending sign-in challenge', () async {
      final now = DateTime.utc(2030, 1, 1);
      final feature = TwoFactorPlugin<Object>(
        store: InMemoryAuthTwoFactorStore(),
        challengeStore: InMemoryAuthTwoFactorChallengeStore(),
        trustedDeviceStore: InMemoryAuthTwoFactorTrustedDeviceStore(),
        secretProtector: const PlaintextAuthTwoFactorSecretProtector(),
      );
      final enrollment = await feature.beginEnrollment('user-1', now: now);
      await feature.verifyEnrollment(
        'user-1',
        generateAuthTotpCode(
          enrollment.secret,
          timestampSeconds: now.millisecondsSinceEpoch ~/ 1000,
        ),
        now: now,
      );

      final challenge = await feature.beginSignInChallenge('user-1', now: now);
      expect(challenge, isNotNull);
      final completion = await feature.completeSignInChallenge(
        challenge!.token,
        generateAuthTotpCode(
          enrollment.secret,
          timestampSeconds: now.millisecondsSinceEpoch ~/ 1000,
        ),
        now: now,
      );
      expect(completion.userId, equals('user-1'));
      expect(
        () => feature.completeSignInChallenge(
          challenge.token,
          'not-a-code',
          now: now,
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            equals('two_factor_invalid_challenge'),
          ),
        ),
      );
    });

    test(
      'atomically completes a pending sign-in with a recovery code',
      () async {
        final now = DateTime.utc(2030, 1, 1);
        final factorStore = InMemoryAuthTwoFactorStore();
        final challengeStore = InMemoryAuthTwoFactorChallengeStore();
        final feature = TwoFactorPlugin<Object>(
          store: factorStore,
          challengeStore: challengeStore,
          pendingRecoveryStore: InMemoryAuthTwoFactorPendingRecoveryStore(
            factorStore: factorStore,
            challengeStore: challengeStore,
          ),
          trustedDeviceStore: InMemoryAuthTwoFactorTrustedDeviceStore(),
          secretProtector: const PlaintextAuthTwoFactorSecretProtector(),
        );
        final enrollment = await feature.beginEnrollment('user-1', now: now);
        final recoveryCodes = await feature.verifyEnrollment(
          'user-1',
          generateAuthTotpCode(
            enrollment.secret,
            timestampSeconds: now.millisecondsSinceEpoch ~/ 1000,
          ),
          now: now,
        );
        expect(
          (await feature.status('user-1', now: now)).recoveryCodesRemaining,
          equals(10),
        );

        final challenge = (await feature.beginSignInChallenge(
          'user-1',
          now: now,
        ))!;
        final completion = await feature.completeRecoverySignInChallenge(
          challenge.token,
          recoveryCodes.codes.first,
          now: now,
        );
        expect(completion.userId, equals('user-1'));
        expect(
          (await feature.status('user-1', now: now)).recoveryCodesRemaining,
          equals(9),
        );
        await expectLater(
          () => feature.completeRecoverySignInChallenge(
            challenge.token,
            'anything',
            now: now,
          ),
          throwsA(
            isA<AuthFlowException>().having(
              (error) => error.code,
              'code',
              equals('two_factor_invalid_challenge'),
            ),
          ),
        );
      },
    );

    test('issues, expires, and revokes trusted devices', () async {
      final now = DateTime.utc(2030, 1, 1);
      final trustedStore = InMemoryAuthTwoFactorTrustedDeviceStore();
      final feature = TwoFactorPlugin<Object>(
        store: InMemoryAuthTwoFactorStore(),
        challengeStore: InMemoryAuthTwoFactorChallengeStore(),
        trustedDeviceStore: trustedStore,
        trustedDeviceTtl: const Duration(days: 30),
        secretProtector: const PlaintextAuthTwoFactorSecretProtector(),
        secretGenerator: _queuedGenerator(),
      );
      final enrollment = await feature.beginEnrollment('user-1', now: now);
      await feature.verifyEnrollment(
        'user-1',
        generateAuthTotpCode(
          enrollment.secret,
          timestampSeconds: now.millisecondsSinceEpoch ~/ 1000,
        ),
        now: now,
      );

      final challenge = (await feature.beginSignInChallenge(
        'user-1',
        now: now,
      ))!;
      final completion = await feature.completeSignInChallenge(
        challenge.token,
        generateAuthTotpCode(
          enrollment.secret,
          timestampSeconds: now.millisecondsSinceEpoch ~/ 1000,
        ),
        trustDevice: true,
        now: now,
      );
      final trusted = completion.trustedDevice!;
      expect(trusted.expiresAt, equals(now.add(const Duration(days: 30))));
      expect(
        await feature.beginSignInChallenge(
          'user-1',
          trustedDeviceToken: trusted.token,
          now: now.add(const Duration(days: 1)),
        ),
        isNull,
      );
      expect(
        await feature.beginSignInChallenge(
          'user-1',
          trustedDeviceToken: trusted.token,
          now: trusted.expiresAt,
        ),
        isNotNull,
      );

      await expectLater(
        () => feature.issueTrustedDevice('user-1', 'not-a-code', now: now),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            equals('two_factor_invalid_code'),
          ),
        ),
      );

      await feature.revokeAllTrustedDevices(
        'user-1',
        now: now.add(const Duration(days: 2)),
      );
      final renewed = await feature.issueTrustedDevice(
        'user-1',
        generateAuthTotpCode(
          enrollment.secret,
          timestampSeconds:
              now.add(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000,
        ),
        now: now.add(const Duration(days: 2)),
      );
      await feature.revokeAllTrustedDevices(
        'user-1',
        now: now.add(const Duration(days: 3)),
      );
      expect(
        trustedStore.findActive(
          'user-1',
          hashOpaqueToken(renewed.token),
          now: now.add(const Duration(days: 3)),
        ),
        isNull,
      );
    });

    test('issues session-bound step-up proofs with bounded expiry', () async {
      final now = DateTime.utc(2030, 1, 1);
      final stepUpStore = InMemoryAuthTwoFactorStepUpStore();
      final feature = TwoFactorPlugin<Object>(
        store: InMemoryAuthTwoFactorStore(),
        challengeStore: InMemoryAuthTwoFactorChallengeStore(),
        trustedDeviceStore: InMemoryAuthTwoFactorTrustedDeviceStore(),
        stepUpStore: stepUpStore,
        stepUpTtl: const Duration(minutes: 5),
        secretProtector: const PlaintextAuthTwoFactorSecretProtector(),
        secretGenerator: _queuedGenerator(),
      );
      final enrollment = await feature.beginEnrollment('user-1', now: now);
      await feature.verifyEnrollment(
        'user-1',
        generateAuthTotpCode(
          enrollment.secret,
          timestampSeconds: now.millisecondsSinceEpoch ~/ 1000,
        ),
        now: now,
      );

      final proof = await feature.verifyStepUp(
        'user-1',
        'session-a',
        generateAuthTotpCode(
          enrollment.secret,
          timestampSeconds: now.millisecondsSinceEpoch ~/ 1000,
        ),
        now: now,
      );
      expect(proof.expiresAt, equals(now.add(const Duration(minutes: 5))));
      expect(
        await feature.isStepUpValid(
          'user-1',
          'session-a',
          proof.token,
          now: now.add(const Duration(minutes: 1)),
        ),
        isTrue,
      );
      expect(
        await feature.isStepUpValid(
          'user-1',
          'session-b',
          proof.token,
          now: now.add(const Duration(minutes: 1)),
        ),
        isFalse,
      );
      expect(
        await feature.isStepUpValid(
          'user-1',
          'session-a',
          proof.token,
          now: proof.expiresAt,
        ),
        isFalse,
      );

      final secondProof = await feature.verifyStepUp(
        'user-1',
        'session-a',
        generateAuthTotpCode(
          enrollment.secret,
          timestampSeconds: now.millisecondsSinceEpoch ~/ 1000,
        ),
        now: now,
      );
      await feature.revokeStepUp('user-1', 'session-a');
      expect(
        stepUpStore.findActive(
          'user-1',
          hashOpaqueToken('session-a'),
          hashOpaqueToken(secondProof.token),
          now: now,
        ),
        isNull,
      );
    });

    test('revokes every step-up proof when two-factor is disabled', () async {
      final now = DateTime.utc(2030, 1, 1);
      final stepUpStore = InMemoryAuthTwoFactorStepUpStore();
      final feature = TwoFactorPlugin<Object>(
        store: InMemoryAuthTwoFactorStore(),
        challengeStore: InMemoryAuthTwoFactorChallengeStore(),
        trustedDeviceStore: InMemoryAuthTwoFactorTrustedDeviceStore(),
        stepUpStore: stepUpStore,
        secretProtector: const PlaintextAuthTwoFactorSecretProtector(),
        secretGenerator: _queuedGenerator(),
      );
      final enrollment = await feature.beginEnrollment('user-1', now: now);
      final code = generateAuthTotpCode(
        enrollment.secret,
        timestampSeconds: now.millisecondsSinceEpoch ~/ 1000,
      );
      await feature.verifyEnrollment('user-1', code, now: now);
      final proof = await feature.verifyStepUp(
        'user-1',
        'session-a',
        code,
        now: now,
      );

      await feature.disable('user-1', code, now: now);

      expect(
        await feature.isStepUpValid(
          'user-1',
          'session-a',
          proof.token,
          now: now,
        ),
        isFalse,
      );
    });

    test(
      'challenge lockout cannot be bypassed with a fresh challenge',
      () async {
        final now = DateTime.utc(2030, 1, 1);
        final factorStore = InMemoryAuthTwoFactorStore();
        final feature = TwoFactorPlugin<Object>(
          store: factorStore,
          challengeStore: InMemoryAuthTwoFactorChallengeStore(),
          trustedDeviceStore: InMemoryAuthTwoFactorTrustedDeviceStore(),
          secretProtector: const PlaintextAuthTwoFactorSecretProtector(),
          secretGenerator: _queuedGenerator(),
          maxFailedVerificationAttempts: 2,
          lockoutDuration: const Duration(minutes: 5),
        );
        final enrollment = await feature.beginEnrollment('user-1', now: now);
        await feature.verifyEnrollment(
          'user-1',
          generateAuthTotpCode(
            enrollment.secret,
            timestampSeconds: now.millisecondsSinceEpoch ~/ 1000,
          ),
          now: now,
        );

        final challenge = (await feature.beginSignInChallenge(
          'user-1',
          now: now,
        ))!;
        await expectLater(
          () => feature.completeSignInChallenge(
            challenge.token,
            'not-a-code',
            now: now,
          ),
          throwsA(
            isA<AuthFlowException>().having(
              (error) => error.code,
              'code',
              equals('two_factor_invalid_code'),
            ),
          ),
        );
        await expectLater(
          () => feature.completeSignInChallenge(
            challenge.token,
            'not-a-code',
            now: now,
          ),
          throwsA(
            isA<AuthFlowException>().having(
              (error) => error.code,
              'code',
              equals('two_factor_challenge_locked'),
            ),
          ),
        );
        expect(
          (await feature.status('user-1', now: now)).lockedUntil,
          isNotNull,
        );
        await expectLater(
          () => feature.beginSignInChallenge('user-1', now: now),
          throwsA(
            isA<AuthFlowException>().having(
              (error) => error.code,
              'code',
              equals('two_factor_locked'),
            ),
          ),
        );
        expect(factorStore.findByUserId('user-1')!.failedVerificationCount, 2);
      },
    );

    test('bounds malformed persisted secrets to an auth error', () async {
      final now = DateTime.utc(2030, 1, 1);
      final store = InMemoryAuthTwoFactorStore();
      store.save(
        AuthTwoFactorRecord(
          userId: 'user-1',
          protectedSecret: 'not-a-base32-secret!',
          verified: true,
          enrollmentExpiresAt: now.add(const Duration(hours: 1)),
        ),
      );
      final feature = TwoFactorPlugin<Object>(
        store: store,
        challengeStore: InMemoryAuthTwoFactorChallengeStore(),
        trustedDeviceStore: InMemoryAuthTwoFactorTrustedDeviceStore(),
        secretProtector: const PlaintextAuthTwoFactorSecretProtector(),
      );

      await expectLater(
        () => feature.verifyTotp('user-1', '000000', now: now),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            equals('two_factor_invalid_code'),
          ),
        ),
      );
    });
  });
}

List<int> Function(int length) _queuedGenerator() {
  final values = <List<int>>[
    List<int>.generate(20, (index) => index + 1),
    ...List<List<int>>.generate(
      10,
      (index) => List<int>.generate(10, (byte) => index + byte + 1),
    ),
  ];
  return (length) {
    final next = values.removeAt(0);
    if (next.length != length) throw StateError('unexpected test size');
    return next;
  };
}
