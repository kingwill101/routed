import 'package:property_testing/property_testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

String _report(PropertyResult result) =>
    'Property failed after ${result.numTests} cases: '
    '${result.error ?? 'unknown failure'}; input=${result.failingInput}; '
    'seed=${result.seed}';

final class _PropertyHasher implements PasswordHasher {
  @override
  String hash(String password) => 'hash:$password';

  @override
  PasswordVerification verify(String password, String encodedHash) =>
      PasswordVerification(
        matches: encodedHash == 'hash:$password',
        needsRehash: false,
      );
}

void main() {
  test(
    'hostile identifiers never cross from email intent to username',
    () async {
      final policy = AuthUsernameIdentifierPolicy();
      final generator = Gen.frequency<String>([
        (6, Chaos.string(minLength: 0, maxLength: 300)),
        (
          4,
          Gen.oneOf<String>([
            '',
            '@',
            'name@',
            '@example.com',
            'name@@example.com',
            'name@invalid domain',
            'name\u0000@example.com',
            '１２３@example.com',
            '<script>@example.com',
            'A' * 300,
          ]),
        ),
      ]);
      final runner = PropertyTestRunner<String>(generator, (input) {
        final resolution = policy.resolve(input);
        if (input.contains('@')) {
          expect(
            resolution == null ||
                resolution.kind == AuthUsernameIdentifierKind.email,
            isTrue,
          );
          expect(policy.normalizeUsername(input), isNull);
        }
        final username = policy.normalizeUsername(input);
        if (username != null) {
          expect(username, matches(RegExp(r'^[a-z0-9._-]{3,32}$')));
          expect(username, isNot(contains('@')));
          expect(policy.normalizeUsername(username), username);
        }
      }, PropertyConfig(numTests: 1000, seed: 20260820));

      final result = await runner.run();
      expect(result.success, isTrue, reason: _report(result));
    },
  );

  test(
    'normalized username collisions always have one opaque winner',
    () async {
      final runner = PropertyTestRunner<int>(
        Gen.integer(min: 100, max: 999999),
        (value) async {
          final plugin = UsernamePlugin<String>();
          AuthRuntime<String>(
            options: AuthOptions<String>(
              providers: const <AuthProvider>[],
              store: InMemoryAuthStore(),
              storeMode: AuthStoreMode.ephemeral,
              passwordHasher: _PropertyHasher(),
              plugins: <AuthServerPlugin<String>>[plugin],
            ),
          );
          final canonical = 'user$value';
          await plugin.register(
            context: 'property-first',
            request: AuthUsernameRegistrationRequest(
              username: ' USER$value ',
              password: 'safe-password-123',
            ),
          );
          await expectLater(
            plugin.register(
              context: 'property-collision',
              request: AuthUsernameRegistrationRequest(
                username: canonical,
                password: 'safe-password-123',
              ),
            ),
            throwsA(
              isA<AuthFlowException>().having(
                (error) => error.code,
                'code',
                'registration_failed',
              ),
            ),
          );
        },
        PropertyConfig(numTests: 250, seed: 20260821),
      );

      final result = await runner.run();
      expect(result.success, isTrue, reason: _report(result));
    },
  );

  test(
    'username mutation responses sanitize hostile secret attributes',
    () async {
      final runner = PropertyTestRunner<String>(
        Chaos.string(minLength: 1, maxLength: 200),
        (secret) {
          final body = AuthUsernameChangeResult(
            username: 'safe-user',
            changed: true,
            user: AuthUser(
              id: 'user-1',
              attributes: <String, dynamic>{
                'username': 'safe-user',
                'passwordResetToken': secret,
                'nested': <String, dynamic>{
                  'credentialSecret': secret,
                  'public': 'safe',
                },
              },
            ),
          ).toJson();
          final attributes = Map<String, dynamic>.from(
            (body['user'] as Map)['attributes'] as Map,
          );
          expect(attributes, isNot(contains('passwordResetToken')));
          expect(
            Map<String, dynamic>.from(attributes['nested'] as Map),
            <String, dynamic>{'public': 'safe'},
          );
          expect(attributes.toString(), isNot(contains('credentialSecret')));
        },
        PropertyConfig(numTests: 250, seed: 20260822),
      );

      final result = await runner.run();
      expect(result.success, isTrue, reason: _report(result));
    },
  );
}
