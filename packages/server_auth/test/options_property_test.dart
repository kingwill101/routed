import 'package:property_testing/property_testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test('property: historical user-data namespaces remain canonical', () async {
    final generator = Gen.frequency<String>([
      (8, Chaos.string(minLength: 0, maxLength: 80)),
      (
        2,
        Gen.oneOf<String>([
          '',
          ' legacy_device',
          'legacy_device ',
          'legacy\nplugin',
          'legacy\u0000plugin',
          'LEGACY_DEVICE',
          'x' * 65,
        ]),
      ),
    ]);
    final runner = PropertyTestRunner<String>(generator, (candidate) async {
      final safe =
          candidate.isNotEmpty &&
          candidate == candidate.trim() &&
          candidate == candidate.toLowerCase() &&
          candidate.length <= 64 &&
          candidate.runes.every((rune) => rune >= 0x20 && rune != 0x7f);
      try {
        final options = AuthOptions<Object>(
          providers: const <AuthProvider>[],
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
          historicalUserDataNamespaces: [candidate],
        );
        expect(safe, isTrue);
        expect(options.historicalUserDataNamespaces, [candidate]);
      } on ArgumentError {
        expect(safe, isFalse);
      }
    }, PropertyConfig(numTests: 256, seed: 20260822));
    final result = await runner.run();

    expect(result.success, isTrue, reason: _propertyReport(result));
  });
}

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
