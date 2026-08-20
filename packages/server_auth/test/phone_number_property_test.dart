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
      store: InMemoryAuthPhoneNumberStore(),
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
        store: InMemoryAuthPhoneNumberStore(),
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
}
