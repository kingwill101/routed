import 'package:property_testing/property_testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

Generator<String> _resetTokens() {
  return Gen.frequency<String>([
    (4, Chaos.string(minLength: 1, maxLength: 200)),
    (
      2,
      Gen.oneOf<String>([
        'reset/../../secret',
        'reset%00token',
        'reset\r\nSet-Cookie: session=attacker',
        'reset<script>alert(1)</script>',
        'пароль-reset-🔐',
        'reset token with spaces',
      ]),
    ),
    (1, Gen.string(minLength: 1, maxLength: 128)),
  ]);
}

String _propertyReport(PropertyResult result) {
  if (result.success) return 'All ${result.numTests} generated cases passed';
  return [
    'Property failed after ${result.numTests} cases',
    'Original input: ${result.originalFailingInput}',
    'Shrunk input: ${result.failingInput}',
    'Shrinks: ${result.numShrinks}',
    'Error: ${result.error}',
    'Seed: ${result.seed}',
  ].join('\n');
}

void main() {
  test(
    'reset tokens remain digest-only and single-use for hostile inputs',
    () async {
      final runner = PropertyTestRunner<String>(_resetTokens(), (
        rawToken,
      ) async {
        final store = InMemoryAuthPasswordResetTokenStore();
        final record = buildAuthPasswordResetToken(
          userId: 'user-1',
          token: rawToken,
          ttl: const Duration(minutes: 10),
          now: DateTime.now().toUtc(),
        );

        expect(record.tokenHash, hasLength(43));
        expect(record.tokenHash, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
        expect(record.tokenHash, isNot(equals(rawToken)));

        await store.save(record);
        expect(await store.consume(rawToken), same(record));
        expect(await store.consume(rawToken), isNull);
      }, PropertyConfig(numTests: 500, seed: 20260819));

      final result = await runner.run();
      expect(result.success, isTrue, reason: _propertyReport(result));
    },
  );
}
