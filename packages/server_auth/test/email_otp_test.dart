import 'package:property_testing/property_testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

const _rateLimitHashKey = 'email-otp-test-rate-limit-key-not-for-production';

void main() {
  group('InMemoryAuthEmailOtpStore', () {
    final createdAt = DateTime.utc(2026, 1, 1, 12);

    AuthEmailOtp record({int maxAttempts = 3}) => AuthEmailOtp(
      id: 'otp-1',
      email: 'ada@example.com',
      codeHash: hashAuthEmailOtpCode('123456'),
      type: AuthEmailOtpType.signIn,
      createdAt: createdAt,
      expiresAt: createdAt.add(const Duration(minutes: 5)),
      maxAttempts: maxAttempts,
    );

    test('rotates by email and purpose and stores only a digest', () async {
      final store = InMemoryAuthEmailOtpStore();
      await store.save(record());
      await store.save(
        AuthEmailOtp(
          id: 'otp-2',
          email: 'ADA@EXAMPLE.COM',
          codeHash: hashAuthEmailOtpCode('654321'),
          type: AuthEmailOtpType.signIn,
          createdAt: createdAt,
          expiresAt: createdAt.add(const Duration(minutes: 5)),
          maxAttempts: 3,
        ),
      );

      expect(
        (await store.verify(
          'ada@example.com',
          AuthEmailOtpType.signIn,
          '123456',
          now: createdAt,
        )).status,
        AuthEmailOtpVerificationStatus.invalid,
      );
      expect(
        (await store.verify(
          'ada@example.com',
          AuthEmailOtpType.signIn,
          '654321',
          now: createdAt,
        )).status,
        AuthEmailOtpVerificationStatus.verified,
      );
      final storage = record().toStorageJson();
      expect(storage.values, isNot(contains('123456')));
      expect(storage.keys, isNot(contains('code')));
    });

    test(
      'invalid attempts eventually lock the OTP and valid codes are one-time',
      () async {
        final store = InMemoryAuthEmailOtpStore();
        await store.save(record(maxAttempts: 2));

        expect(
          (await store.verify(
            'ada@example.com',
            AuthEmailOtpType.signIn,
            '000000',
            now: createdAt,
          )).status,
          AuthEmailOtpVerificationStatus.invalid,
        );
        expect(
          (await store.verify(
            'ada@example.com',
            AuthEmailOtpType.signIn,
            '000000',
            now: createdAt,
          )).status,
          AuthEmailOtpVerificationStatus.tooManyAttempts,
        );
        expect(
          (await store.verify(
            'ada@example.com',
            AuthEmailOtpType.signIn,
            '123456',
            now: createdAt,
          )).status,
          AuthEmailOtpVerificationStatus.tooManyAttempts,
        );
      },
    );

    test('expired codes cannot be verified', () async {
      final store = InMemoryAuthEmailOtpStore();
      await store.save(record());

      expect(
        (await store.verify(
          'ada@example.com',
          AuthEmailOtpType.signIn,
          '123456',
          now: createdAt.add(const Duration(minutes: 5)),
        )).status,
        AuthEmailOtpVerificationStatus.expired,
      );
    });
  });

  group('EmailOtpPlugin', () {
    test('requires a production-strength limiter digest key', () {
      expect(
        () =>
            EmailOtpPlugin<Object>(sendCode: (_) {}, rateLimitHashKey: 'short'),
        throwsArgumentError,
      );
    });

    test(
      'property: canonical emails have bounded keyed OTP-independent limiter IDs',
      () async {
        final plugin = EmailOtpPlugin<Object>(
          sendCode: (_) {},
          rateLimitHashKey: _rateLimitHashKey,
        );
        final send =
            plugin.endpoints.singleWhere(
                  (endpoint) => endpoint.id == 'emailOtp.sendVerificationOtp',
                )
                as AuthEndpointRateLimitIdentifierDescriptor;
        final check =
            plugin.endpoints.singleWhere(
                  (endpoint) => endpoint.id == 'emailOtp.checkVerificationOtp',
                )
                as AuthEndpointRateLimitIdentifierDescriptor;
        final expected = send.resolveRateLimitIdentifier(
          AuthEndpointRequest(
            body: const <String, dynamic>{
              'email': ' Ada@Example.COM ',
              'type': 'sign-in',
            },
          ),
        );

        expect(expected, startsWith('email:'));
        expect(
          expected!.length,
          lessThanOrEqualTo(authRateLimitIdentifierMaximumLength),
        );
        expect(expected, isNot(contains('ada@example.com')));
        expect(
          send.resolveRateLimitIdentifier(
            AuthEndpointRequest(
              body: const <String, dynamic>{
                'email': 'ada@example.com',
                'type': 'email-verification',
              },
            ),
          ),
          expected,
        );

        final runner = PropertyTestRunner<String>(
          Gen.frequency<String>(<(int, Generator<String>)>[
            (7, Chaos.string(minLength: 0, maxLength: 512)),
            (
              3,
              Gen.oneOf<String>(<String>[
                '123456',
                '123456\r\nAuthorization: Bearer secret',
                '<script>alert(1)</script>',
                '9' * 4096,
              ]),
            ),
          ]),
          (otp) {
            final identifier = check.resolveRateLimitIdentifier(
              AuthEndpointRequest(
                body: <String, dynamic>{
                  'email': 'ADA@example.com',
                  'type': 'sign-in',
                  'otp': otp,
                },
              ),
            );
            expect(identifier, expected);
            if (otp.isNotEmpty) expect(identifier, isNot(contains(otp)));
          },
          PropertyConfig(numTests: 500, seed: 20260820),
        );
        final result = await runner.run();
        expect(result.success, isTrue, reason: '${result.error}');

        expect(send.resolveRateLimitIdentifier(AuthEndpointRequest()), isNull);
        expect(
          send.resolveRateLimitIdentifier(
            AuthEndpointRequest(body: const {'email': 7}),
          ),
          isNull,
        );
        expect(
          send.resolveRateLimitIdentifier(
            AuthEndpointRequest(body: const {'email': 'not-an-email'}),
          ),
          isNull,
        );
      },
    );

    test('sends a hashed OTP and signs in a new user once verified', () async {
      final store = InMemoryAuthStore();
      String? sentCode;
      final feature = EmailOtpPlugin<Object>(
        rateLimitHashKey: _rateLimitHashKey,
        generateOtp: (_) => '123456',
        sendCode: (delivery) {
          sentCode = delivery.code;
          expect(delivery.email, 'ada@example.com');
          expect(delivery.type, AuthEmailOtpType.signIn);
        },
      );
      final runtime = AuthRuntime<Object>(
        options: AuthOptions<Object>(
          providers: const [],
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          plugins: [feature],
        ),
      );

      await feature.sendVerificationOtp(
        context: Object(),
        email: ' ADA@EXAMPLE.COM ',
        type: AuthEmailOtpType.signIn,
        now: DateTime.utc(2026),
      );
      final user = await feature.signInWithOtp(
        context: Object(),
        email: 'ada@example.com',
        code: sentCode!,
        now: DateTime.utc(2026, 1, 1, 0, 1),
      );

      expect(user.user.email, 'ada@example.com');
      expect(user.user.attributes['emailVerified'], isTrue);
      expect(await store.users.findByEmail('ada@example.com'), isNotNull);
      expect(runtime.hasPlugin(authEmailOtpPluginId), isTrue);
      await expectLater(
        feature.signInWithOtp(
          context: Object(),
          email: 'ada@example.com',
          code: sentCode!,
          now: DateTime.utc(2026, 1, 1, 0, 1),
        ),
        _flow('invalid_otp'),
      );
    });

    test(
      'disableSignUp blocks unknown addresses and verification updates users',
      () async {
        final store = InMemoryAuthStore();
        final user = await store.users.create(
          AuthUser(
            id: 'user-1',
            email: 'ada@example.com',
            attributes: const {'emailVerified': false},
          ),
        );
        final feature = EmailOtpPlugin<Object>(
          rateLimitHashKey: _rateLimitHashKey,
          disableSignUp: true,
          generateOtp: (_) => '123456',
          sendCode: (delivery) async {},
        );
        AuthRuntime<Object>(
          options: AuthOptions<Object>(
            providers: const [],
            store: store,
            storeMode: AuthStoreMode.ephemeral,
            plugins: [feature],
          ),
        );

        await feature.sendVerificationOtp(
          context: Object(),
          email: user.email!,
          type: AuthEmailOtpType.emailVerification,
        );
        final updated = await feature.verifyEmail(
          userId: user.id,
          code: '123456',
        );
        expect(updated.attributes['emailVerified'], isTrue);

        await feature.sendVerificationOtp(
          context: Object(),
          email: 'new@example.com',
          type: AuthEmailOtpType.signIn,
        );
        await expectLater(
          feature.signInWithOtp(
            context: Object(),
            email: 'new@example.com',
            code: '123456',
          ),
          _flow('user_not_found'),
        );
      },
    );
  });
}

Matcher _flow(String code) => throwsA(
  isA<AuthFlowException>().having((error) => error.code, 'code', code),
);
