import 'package:property_testing/property_testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

const _hashKey = '0123456789abcdef0123456789abcdef';

Generator<String> _hostilePhoneNumbers() =>
    Gen.frequency<String>(<(int, Generator<String>)>[
      (6, Chaos.string(minLength: 0, maxLength: 512)),
      (
        4,
        Gen.oneOf<String>(<String>[
          '+1\r\nSet-Cookie: session=attacker',
          '+1\u00005551234',
          '+１２３４５６７８９',
          '<script>alert(1)</script>',
          "' OR '1'='1",
          '+${'9' * 4096}',
        ]),
      ),
    ]);

Generator<String> _hostileCodes() =>
    Gen.frequency<String>(<(int, Generator<String>)>[
      (6, Chaos.string(minLength: 0, maxLength: 512)),
      (
        4,
        Gen.oneOf<String>(<String>[
          '１２３４５６',
          '123456\u0000',
          '123456\r\nAuthorization: Bearer secret',
          '<script>alert(1)</script>',
          "' OR '1'='1",
          '9' * 4096,
        ]),
      ),
    ]);

String _report(PropertyResult result) {
  if (result.success) return 'All ${result.numTests} generated cases passed';
  return <Object?>[
    'Property failed after ${result.numTests} cases',
    'Input: ${result.originalFailingInput}',
    'Shrunk: ${result.failingInput}',
    'Error: ${result.error}',
    'Seed: ${result.seed}',
  ].join('\n');
}

void main() {
  test('property: normalization emits only canonical E.164', () async {
    const policy = AuthE164PhoneNumberPolicy();
    final runner = PropertyTestRunner<String>(_hostilePhoneNumbers(), (input) {
      final normalized = policy.normalize(input);
      if (normalized != null) {
        expect(normalized, matches(RegExp(r'^\+[1-9][0-9]{1,14}$')));
        expect(normalized.length, lessThanOrEqualTo(16));
      }
    }, PropertyConfig(numTests: 1000, seed: 20260819));

    final result = await runner.run();
    expect(result.success, isTrue, reason: _report(result));
  });

  test('property: hostile phone inputs remain stable public errors', () async {
    final plugin = PhoneNumberPlugin<Object>(
      sendCode: (_) {},
      codeHashKey: _hashKey,
      generateCode: (_) => '123456',
    );
    AuthRuntime<Object>(
      options: AuthOptions<Object>(
        providers: const <AuthProvider>[],
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        plugins: <AuthServerPlugin<Object>>[plugin],
      ),
    );
    final runner = PropertyTestRunner<String>(_hostilePhoneNumbers(), (
      input,
    ) async {
      if (const AuthE164PhoneNumberPolicy().normalize(input) != null) return;
      await expectLater(
        () => plugin.issueCode(context: Object(), phoneNumber: input),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'invalid_phone_number',
          ),
        ),
      );
    }, PropertyConfig(numTests: 500, seed: 20260820));

    final result = await runner.run();
    expect(result.success, isTrue, reason: _report(result));
  });

  test('property: hostile codes never escape as diagnostic errors', () async {
    final runner = PropertyTestRunner<String>(_hostileCodes(), (input) async {
      if (RegExp(r'^\s*123456\s*$').hasMatch(input)) return;
      final plugin = PhoneNumberPlugin<Object>(
        sendCode: (_) {},
        codeHashKey: _hashKey,
        generateCode: (_) => '123456',
      );
      AuthRuntime<Object>(
        options: AuthOptions<Object>(
          providers: const <AuthProvider>[],
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          plugins: <AuthServerPlugin<Object>>[plugin],
        ),
      );
      await plugin.issueCode(context: Object(), phoneNumber: '+18765551234');
      await expectLater(
        () => plugin.verifyCode(
          context: Object(),
          phoneNumber: '+18765551234',
          code: input,
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            anyOf('invalid_phone_code', 'phone_code_too_many_attempts'),
          ),
        ),
      );
    }, PropertyConfig(numTests: 500, seed: 20260821));

    final result = await runner.run();
    expect(result.success, isTrue, reason: _report(result));
  });

  test(
    'property: limiter keys are bounded and independent of OTP input',
    () async {
      final plugin = PhoneNumberPlugin<Object>(
        sendCode: (_) {},
        codeHashKey: _hashKey,
      );
      final verifyEndpoint =
          plugin.endpoints
                  .where((endpoint) => endpoint.id == 'phoneNumber.verifyCode')
                  .single
              as AuthEndpointRateLimitIdentifierDescriptor;
      final expected = verifyEndpoint.resolveRateLimitIdentifier(
        AuthEndpointRequest(
          body: const <String, dynamic>{
            'phoneNumber': '+18765551234',
            'code': 'baseline-code',
          },
        ),
      );
      final runner = PropertyTestRunner<String>(_hostileCodes(), (code) {
        final identifier = verifyEndpoint.resolveRateLimitIdentifier(
          AuthEndpointRequest(
            body: <String, dynamic>{
              'phoneNumber': ' +18765551234 ',
              'code': code,
            },
          ),
        );
        expect(identifier, expected);
        expect(identifier, isNotNull);
        expect(
          identifier!.length,
          lessThanOrEqualTo(authRateLimitIdentifierMaximumLength),
        );
        expect(identifier, isNot(contains('+18765551234')));
        if (code.isNotEmpty) expect(identifier, isNot(contains(code)));
      }, PropertyConfig(numTests: 500, seed: 20260823));

      final result = await runner.run();
      expect(result.success, isTrue, reason: _report(result));
    },
  );

  test(
    'property: hostile state sequences preserve OTP transaction invariants',
    () async {
      final generator = Gen.integer(
        min: -0x7fffffff,
        max: 0x7fffffff,
      ).list(minLength: 1, maxLength: 100);
      final runner = PropertyTestRunner<List<int>>(generator, (
        operations,
      ) async {
        final backend = InMemoryAuthStore(maxPhoneNumberVerifications: 16);
        backend.bindUserDeletionPlanContributors(const []);
        final now = DateTime.utc(2030, 1, 1);
        var activeDigest = 'digest-initial';
        var issueSequence = 0;
        var verifiedForActiveIssue = 0;
        String? activeUserId;

        for (var index = 0; index < operations.length; index++) {
          final shape = operations[index].abs() % 7;
          switch (shape) {
            case 0:
              issueSequence++;
              activeDigest = 'digest-$issueSequence-${operations[index]}';
              verifiedForActiveIssue = 0;
              await backend.issuePhoneNumberCode(
                AuthPhoneNumberIssueCodeCommand(
                  verification: AuthPhoneNumberVerification(
                    id: 'issue-$issueSequence',
                    phoneNumber: '+18765551234',
                    codeDigest: activeDigest,
                    createdAt: now,
                    expiresAt: now.add(const Duration(minutes: 5)),
                    maxAttempts: 3,
                  ),
                ),
              );
            case 1:
              final userId = activeUserId ?? 'state-user-$issueSequence';
              final result = await backend.verifyPhoneNumberCode(
                AuthPhoneNumberVerifyCodeCommand(
                  phoneNumber: '+18765551234',
                  codeDigest: activeDigest,
                  now: now,
                  candidateUser: AuthUser(id: userId),
                ),
              );
              if (result.status == AuthPhoneNumberVerifyStatus.verified) {
                verifiedForActiveIssue++;
                activeUserId = result.user!.id;
              }
            case 2:
              final result = await backend.verifyPhoneNumberCode(
                AuthPhoneNumberVerifyCodeCommand(
                  phoneNumber: '+18765551234',
                  codeDigest: 'hostile-$index-${operations[index]}',
                  now: now,
                ),
              );
              expect(
                result.verification?.attempts ?? 0,
                inInclusiveRange(0, 3),
              );
            case 3:
              final candidateId = activeUserId ?? 'state-user-$issueSequence';
              final results = await Future.wait([
                backend.verifyPhoneNumberCode(
                  AuthPhoneNumberVerifyCodeCommand(
                    phoneNumber: '+18765551234',
                    codeDigest: activeDigest,
                    now: now,
                    candidateUser: AuthUser(id: candidateId),
                  ),
                ),
                backend.verifyPhoneNumberCode(
                  AuthPhoneNumberVerifyCodeCommand(
                    phoneNumber: '+18765551234',
                    codeDigest: activeDigest,
                    now: now,
                    candidateUser: AuthUser(id: candidateId),
                  ),
                ),
              ]);
              verifiedForActiveIssue += results
                  .where(
                    (result) =>
                        result.status == AuthPhoneNumberVerifyStatus.verified,
                  )
                  .length;
              final verified = results
                  .where(
                    (result) =>
                        result.status == AuthPhoneNumberVerifyStatus.verified,
                  )
                  .firstOrNull;
              activeUserId ??= verified?.user?.id;
            case 4:
              await backend.verifyPhoneNumberCode(
                AuthPhoneNumberVerifyCodeCommand(
                  phoneNumber: '+18765551234',
                  codeDigest: activeDigest,
                  now: now.add(const Duration(hours: 1)),
                ),
              );
            case 5:
              final userId = activeUserId;
              if (userId != null) {
                await backend.userDeletionCoordinator.deleteUser(userId);
                activeUserId = null;
              }
            case 6:
              final hostilePhone = operations[index].isEven
                  ? '+1\r\nSet-Cookie: attacker=true'
                  : '+１２３４５６';
              expect(
                () => AuthPhoneNumberVerifyCodeCommand(
                  phoneNumber: hostilePhone,
                  codeDigest: activeDigest,
                  now: now,
                ),
                throwsArgumentError,
              );
          }

          expect(verifiedForActiveIssue, lessThanOrEqualTo(1));
          final identity = await backend.findPhoneNumberIdentity(
            '+18765551234',
          );
          if (identity != null) {
            expect(
              await backend.findPhoneNumberIdentityForUser(identity.userId),
              same(identity),
            );
            final user = await backend.users.findById(identity.userId);
            expect(user, isNotNull);
            expect(user!.attributes['phoneNumber'], identity.phoneNumber);
            expect(user.attributes['phoneNumberVerified'], isTrue);
          }
        }
      }, PropertyConfig(numTests: 250, seed: 20260824));

      final result = await runner.run();
      expect(result.success, isTrue, reason: _report(result));
    },
  );
}
