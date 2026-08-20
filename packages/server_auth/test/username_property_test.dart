import 'package:property_testing/property_testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

String _report(PropertyResult result) =>
    'Property failed after ${result.numTests} cases: '
    '${result.error ?? 'unknown failure'}; input=${result.failingInput}; '
    'seed=${result.seed}';

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
}
