import 'package:property_testing/property_testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

Generator<String> _hostileSecrets() => Gen.frequency<String>([
  (4, Chaos.string(minLength: 0, maxLength: 180)),
  (
    2,
    Gen.oneOf<String>([
      'captcha-token',
      'password-secret',
      '<script>token</script>',
      'token\r\nSet-Cookie: leaked=1',
      'a' * 2048,
    ]),
  ),
]);

String _propertyReport(PropertyResult result) {
  if (result.success) return 'All ${result.numTests} generated cases passed';
  return [
    'Property failed after ${result.numTests} generated cases',
    'Original input: ${result.originalFailingInput}',
    'Shrunk input: ${result.failingInput}',
    'Error: ${result.error}',
    'Seed: ${result.seed}',
  ].join('\n');
}

void _expectNoSensitiveKeys(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      final normalized = entry.key.toString().toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9]'),
        '',
      );
      expect(
        normalized,
        isNot(anyOf('password', 'passwordhash', 'token', 'captchatoken')),
      );
      _expectNoSensitiveKeys(entry.value);
    }
  } else if (value is Iterable) {
    for (final item in value) {
      _expectNoSensitiveKeys(item);
    }
  }
}

void main() {
  test(
    'hostile captcha and password values never survive public projections',
    () async {
      final runner = PropertyTestRunner<String>(_hostileSecrets(), (secret) {
        final user = AuthUser(
          id: 'user-1',
          attributes: <String, dynamic>{
            'captchaToken': secret,
            'password': secret,
            'public': 'safe',
            'nested': <String, dynamic>{'token': secret, 'safe': true},
          },
        );
        final credentials = AuthCredentials(
          password: secret,
          attributes: <String, dynamic>{
            'captchaToken': secret,
            'password': secret,
            'public': 'safe',
          },
        );

        final projections = <Object?>[
          user.toJson(),
          user.redacted().toJson(),
          credentials.redacted().attributes,
        ];
        for (final projection in projections) {
          _expectNoSensitiveKeys(projection);
          if (secret.isNotEmpty) {
            expect(projection.toString(), isNot(contains(secret)));
          }
        }
      }, PropertyConfig(numTests: 250, seed: 20260819));

      final result = await runner.run();
      expect(result.success, isTrue, reason: _propertyReport(result));
    },
  );

  test(
    'malformed captcha inputs always fail before the provider boundary',
    () async {
      final runner = PropertyTestRunner<String>(_hostileSecrets(), (
        token,
      ) async {
        var calls = 0;
        final plugin = CaptchaPlugin<String>(
          verifier: _PropertyCaptchaVerifier(() {
            calls += 1;
            return const AuthCaptchaVerificationResult.accepted();
          }),
          config: const AuthCaptchaPluginConfig(maxTokenLength: 16),
        );
        final runtime = AuthRuntime<String>(
          options: AuthOptions<String>(
            providers: const <AuthProvider>[],
            store: InMemoryAuthStore(),
            storeMode: AuthStoreMode.ephemeral,
            plugins: <AuthServerPlugin<String>>[plugin],
          ),
        );

        if (token.length > 16 || token.trim().isEmpty) {
          await expectLater(
            runtime.registry.enforceCredentialPolicy(
              AuthCredentialPolicyRequest<String>(
                context: 'property',
                provider: CredentialsProvider(),
                operation: AuthCredentialPolicyOperation.signIn,
                verificationToken: token,
              ),
            ),
            throwsA(isA<AuthFlowException>()),
          );
          expect(calls, 0);
        }
      }, PropertyConfig(numTests: 250, seed: 20260819));

      final result = await runner.run();
      expect(result.success, isTrue, reason: _propertyReport(result));
    },
  );
}

final class _PropertyCaptchaVerifier implements AuthCaptchaVerifier<String> {
  _PropertyCaptchaVerifier(this.onCall);

  final AuthCaptchaVerificationResult Function() onCall;

  @override
  AuthCaptchaVerificationResult verify(
    AuthCaptchaVerificationRequest<String> request,
  ) => onCall();
}
