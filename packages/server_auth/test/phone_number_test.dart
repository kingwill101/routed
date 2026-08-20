import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

const _hashKey = '0123456789abcdef0123456789abcdef';

void main() {
  group('AuthE164PhoneNumberPolicy', () {
    const policy = AuthE164PhoneNumberPolicy();

    test('accepts only canonical E.164 input', () {
      expect(policy.normalize(' +18765551234 '), '+18765551234');
      expect(policy.normalize('+12025550123'), '+12025550123');
      for (final value in <String>[
        '18765551234',
        '+0123456789',
        '+1 876 555 1234',
        '+1-876-555-1234',
        '+１２３４５６７８９',
        '+1\u0000555',
        '+1234567890123456',
        '+1',
      ]) {
        expect(policy.normalize(value), isNull, reason: value);
      }
    });
  });

  group('InMemoryAuthPhoneNumberStore', () {
    final now = DateTime.utc(2026, 8, 19, 12);

    AuthPhoneNumberVerification verification({
      String id = 'verification-1',
      String digest = 'digest-1',
      int attempts = 0,
      int maxAttempts = 3,
    }) => AuthPhoneNumberVerification(
      id: id,
      phoneNumber: '+18765551234',
      codeDigest: digest,
      createdAt: now,
      expiresAt: now.add(const Duration(minutes: 5)),
      maxAttempts: maxAttempts,
      attempts: attempts,
    );

    test('rejects non-positive storage bounds at runtime', () {
      expect(
        () => InMemoryAuthPhoneNumberStore(maxVerifications: 0),
        throwsArgumentError,
      );
    });

    test('atomically consumes a challenge once', () async {
      final store = InMemoryAuthPhoneNumberStore();
      await store.saveVerification(verification());

      final results = await Future.wait(
        List<Future<AuthPhoneNumberVerificationResult>>.generate(
          32,
          (_) =>
              store.consumeVerification('+18765551234', 'digest-1', now: now),
        ),
      );

      expect(
        results.where(
          (result) =>
              result.status == AuthPhoneNumberVerificationStatus.verified,
        ),
        hasLength(1),
      );
      expect(
        results.where(
          (result) =>
              result.status == AuthPhoneNumberVerificationStatus.invalid,
        ),
        hasLength(31),
      );
    });

    test('locks a challenge after its bounded attempts', () async {
      final store = InMemoryAuthPhoneNumberStore();
      await store.saveVerification(verification(maxAttempts: 2));

      expect(
        (await store.consumeVerification(
          '+18765551234',
          'wrong',
          now: now,
        )).status,
        AuthPhoneNumberVerificationStatus.invalid,
      );
      expect(
        (await store.consumeVerification(
          '+18765551234',
          'wrong',
          now: now,
        )).status,
        AuthPhoneNumberVerificationStatus.tooManyAttempts,
      );
      expect(
        (await store.consumeVerification(
          '+18765551234',
          'digest-1',
          now: now,
        )).status,
        AuthPhoneNumberVerificationStatus.tooManyAttempts,
      );
    });

    test('expires challenges at the exact configured deadline', () async {
      final store = InMemoryAuthPhoneNumberStore();
      await store.saveVerification(verification());

      expect(
        (await store.consumeVerification(
          '+18765551234',
          'digest-1',
          now: now.add(const Duration(minutes: 5)),
        )).status,
        AuthPhoneNumberVerificationStatus.expired,
      );
    });

    test('conditional deletion cannot remove a newer issuance', () async {
      final store = InMemoryAuthPhoneNumberStore();
      await store.saveVerification(verification());
      await store.saveVerification(
        verification(id: 'verification-2', digest: 'digest-2'),
      );

      expect(
        await store.deleteVerificationIfCurrent(
          '+18765551234',
          'verification-1',
        ),
        isFalse,
      );
      expect(
        (await store.consumeVerification(
          '+18765551234',
          'digest-2',
          now: now,
        )).status,
        AuthPhoneNumberVerificationStatus.verified,
      );
    });

    test('deletes identity and outstanding challenges for a user', () async {
      final store = InMemoryAuthPhoneNumberStore();
      await store.bindIdentity(
        AuthPhoneNumberIdentity(
          phoneNumber: '+18765551234',
          userId: 'user-1',
          createdAt: now,
          verifiedAt: now,
        ),
      );
      await store.saveVerification(verification());

      await store.deleteForUser('user-1');

      expect(await store.findIdentity('+18765551234'), isNull);
      expect(
        (await store.consumeVerification(
          '+18765551234',
          'digest-1',
          now: now,
        )).status,
        AuthPhoneNumberVerificationStatus.invalid,
      );
    });
  });

  group('PhoneNumberPlugin', () {
    test(
      'derives one bounded keyed limiter identifier from decoded requests',
      () {
        final plugin = PhoneNumberPlugin<Object>(
          store: InMemoryAuthPhoneNumberStore(),
          sendCode: (_) {},
          codeHashKey: _hashKey,
        );
        final endpoints = <String, AuthEndpointRateLimitIdentifierDescriptor>{
          for (final endpoint in plugin.endpoints)
            endpoint.id: endpoint as AuthEndpointRateLimitIdentifierDescriptor,
        };
        final sendKey = endpoints['phoneNumber.sendCode']!
            .resolveRateLimitIdentifier(const <String, dynamic>{
              'phoneNumber': ' +18765551234 ',
            });
        final verifyKey = endpoints['phoneNumber.verifyCode']!
            .resolveRateLimitIdentifier(const <String, dynamic>{
              'phoneNumber': '+18765551234',
              'code': '123456',
            });
        final otherCodeKey = endpoints['phoneNumber.verifyCode']!
            .resolveRateLimitIdentifier(const <String, dynamic>{
              'phoneNumber': '+18765551234',
              'code': 'never-copy-this-otp',
            });

        expect(sendKey, startsWith('phone:'));
        expect(sendKey, verifyKey);
        expect(verifyKey, otherCodeKey);
        expect(sendKey, hasLength(49));
        expect(sendKey!.length, lessThan(authRateLimitIdentifierMaximumLength));
        expect(sendKey, isNot(contains('+18765551234')));
        expect(sendKey, isNot(contains('123456')));
        expect(sendKey, isNot(contains('never-copy-this-otp')));
        expect(
          endpoints['phoneNumber.sendCode']!.resolveRateLimitIdentifier(
            const <String, dynamic>{'phoneNumber': 'not-a-phone'},
          ),
          isNull,
        );
        expect(
          endpoints['phoneNumber.verifyCode']!.resolveRateLimitIdentifier(
            const <String, dynamic>{'phoneNumber': '+18765551234'},
          ),
          isNull,
        );
      },
    );

    test('verification responses defer token projection to the host', () async {
      final intent = AuthPhoneNumberVerifyResponse(
        phoneNumber: '+18765551234',
        user: AuthUser(id: 'user-1'),
      ).toAuthenticationIntent();
      final response = await intent.projectResponse(
        AuthSession(
          user: AuthUser(id: 'user-1'),
          expiresAt: DateTime.utc(2030),
          strategy: AuthSessionStrategy.jwt,
          token: 'secret-jwt',
        ).toJson(),
      );

      expect(intent.authenticationMethod, authPhoneNumberAuthenticationMethod);
      expect((response as Map<String, dynamic>)['user'], isNotNull);
      expect(response, isNot(contains('token')));
      expect(response.toString(), isNot(contains('secret-jwt')));
    });

    test('requires a production-strength code digest key', () {
      expect(
        () => PhoneNumberPlugin<Object>(
          store: InMemoryAuthPhoneNumberStore(),
          sendCode: (_) {},
          codeHashKey: 'short',
        ),
        throwsArgumentError,
      );
    });

    test('delivers one raw code while persisting only a digest', () async {
      final store = _CapturingPhoneStore();
      String? delivered;
      final plugin = PhoneNumberPlugin<Object>(
        store: store,
        sendCode: (delivery) => delivered = delivery.code,
        codeHashKey: _hashKey,
        generateCode: (_) => '123456',
      );
      _runtime(plugin);

      await plugin.issueCode(
        context: Object(),
        phoneNumber: ' +18765551234 ',
        now: DateTime.utc(2026),
      );

      expect(delivered, '123456');
      final storage = store.lastVerification!.toStorageJson();
      expect(storage.values, isNot(contains('123456')));
      expect(storage.keys, isNot(contains('code')));
      expect(store.lastVerification!.codeDigest, isNot('123456'));
    });

    test(
      'signs up once, marks verification, and issues a named session',
      () async {
        final store = InMemoryAuthPhoneNumberStore();
        final plugin = PhoneNumberPlugin<Object>(
          store: store,
          sendCode: (_) {},
          codeHashKey: _hashKey,
          allowSignUp: true,
          generateCode: (_) => '123456',
        );
        final runtime = _runtime(plugin);

        await plugin.issueCode(
          context: Object(),
          phoneNumber: '+18765551234',
          now: DateTime.utc(2026),
        );
        final result = await plugin.verifyCode(
          context: Object(),
          phoneNumber: '+18765551234',
          code: '123456',
          name: 'Ada',
          now: DateTime.utc(2026, 1, 1, 0, 1),
        );

        expect(result.user.name, 'Ada');
        expect(result.user.attributes['phoneNumberVerified'], isTrue);
        expect(runtime.hasPlugin(authPhoneNumberPluginId), isTrue);
        await expectLater(
          () => plugin.verifyCode(
            context: Object(),
            phoneNumber: '+18765551234',
            code: '123456',
            now: DateTime.utc(2026, 1, 1, 0, 1),
          ),
          _flow('invalid_phone_code'),
        );
      },
    );

    test(
      'removes an undelivered challenge without deleting a replacement',
      () async {
        final store = InMemoryAuthPhoneNumberStore();
        late PhoneNumberPlugin<Object> plugin;
        plugin = PhoneNumberPlugin<Object>(
          store: store,
          codeHashKey: _hashKey,
          generateCode: (_) => '123456',
          sendCode: (delivery) async {
            await store.saveVerification(
              AuthPhoneNumberVerification(
                id: 'replacement',
                phoneNumber: delivery.phoneNumber,
                codeDigest: 'replacement-digest',
                createdAt: DateTime.utc(2026),
                expiresAt: DateTime.utc(2026).add(const Duration(minutes: 5)),
                maxAttempts: 3,
              ),
            );
            throw StateError('provider unavailable');
          },
        );
        _runtime(plugin);

        await expectLater(
          () => plugin.issueCode(
            context: Object(),
            phoneNumber: '+18765551234',
            now: DateTime.utc(2026),
          ),
          throwsStateError,
        );
        expect(
          await store.deleteVerificationIfCurrent(
            '+18765551234',
            'replacement',
          ),
          isTrue,
        );
      },
    );

    test('keeps sign-up opt-in and rotates prior challenges', () async {
      final store = InMemoryAuthPhoneNumberStore();
      final codes = <String>['111111', '222222'];
      final plugin = PhoneNumberPlugin<Object>(
        store: store,
        sendCode: (_) {},
        codeHashKey: _hashKey,
        generateCode: (_) => codes.removeAt(0),
      );
      _runtime(plugin);

      await plugin.issueCode(
        context: Object(),
        phoneNumber: '+18765551234',
        now: DateTime.utc(2026),
      );
      await plugin.issueCode(
        context: Object(),
        phoneNumber: '+18765551234',
        now: DateTime.utc(2026, 1, 1, 0, 1),
      );
      await expectLater(
        () => plugin.verifyCode(
          context: Object(),
          phoneNumber: '+18765551234',
          code: '111111',
          now: DateTime.utc(2026, 1, 1, 0, 2),
        ),
        _flow('invalid_phone_code'),
      );
      await expectLater(
        () => plugin.verifyCode(
          context: Object(),
          phoneNumber: '+18765551234',
          code: '222222',
          now: DateTime.utc(2026, 1, 1, 0, 2),
        ),
        _flow('user_not_found'),
      );
      expect(await store.findIdentity('+18765551234'), isNull);
    });

    test('participates in reversible user deletion', () async {
      final store = InMemoryAuthPhoneNumberStore();
      final plugin = PhoneNumberPlugin<Object>(
        store: store,
        sendCode: (_) {},
        codeHashKey: _hashKey,
      );
      _runtime(plugin);
      final now = DateTime.utc(2026);
      await store.bindIdentity(
        AuthPhoneNumberIdentity(
          phoneNumber: '+18765551234',
          userId: 'user-1',
          createdAt: now,
          verifiedAt: now,
        ),
      );
      final checkpoint = plugin.checkpointUserData('user-1');

      await plugin.deleteUserData('user-1');
      expect(await store.findIdentity('+18765551234'), isNull);
      await checkpoint.restore();
      expect(await store.findIdentity('+18765551234'), isNotNull);
    });
  });
}

AuthRuntime<Object> _runtime(PhoneNumberPlugin<Object> plugin) =>
    AuthRuntime<Object>(
      options: AuthOptions<Object>(
        providers: const <AuthProvider>[],
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        plugins: <AuthServerPlugin<Object>>[plugin],
      ),
    );

Matcher _flow(String code) => throwsA(
  isA<AuthFlowException>().having((error) => error.code, 'code', code),
);

final class _CapturingPhoneStore implements AuthPhoneNumberStore {
  final InMemoryAuthPhoneNumberStore delegate = InMemoryAuthPhoneNumberStore();
  AuthPhoneNumberVerification? lastVerification;

  @override
  Future<void> saveVerification(AuthPhoneNumberVerification verification) {
    lastVerification = verification;
    return delegate.saveVerification(verification);
  }

  @override
  Future<AuthPhoneNumberVerificationResult> consumeVerification(
    String phoneNumber,
    String codeDigest, {
    DateTime? now,
  }) => delegate.consumeVerification(phoneNumber, codeDigest, now: now);

  @override
  Future<bool> deleteVerificationIfCurrent(
    String phoneNumber,
    String verificationId,
  ) => delegate.deleteVerificationIfCurrent(phoneNumber, verificationId);

  @override
  Future<AuthPhoneNumberIdentity?> findIdentity(String phoneNumber) =>
      delegate.findIdentity(phoneNumber);

  @override
  Future<AuthPhoneNumberIdentity> bindIdentity(
    AuthPhoneNumberIdentity identity,
  ) => delegate.bindIdentity(identity);

  @override
  Future<void> deleteForUser(String userId) => delegate.deleteForUser(userId);
}
