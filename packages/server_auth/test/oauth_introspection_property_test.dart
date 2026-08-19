import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:property_testing/property_testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

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
    'introspection cache evicts the oldest entry for arbitrary token streams',
    () async {
      final tokens = Chaos.string(
        minLength: 1,
        maxLength: 128,
      ).list(minLength: 1, maxLength: 80);
      final runner = PropertyTestRunner<List<String>>(tokens, (values) async {
        const maxEntries = 4;
        var requestCount = 0;
        final introspector = OAuth2TokenIntrospector(
          OAuthIntrospectionOptions(
            endpoint: Uri.parse('https://auth.test/introspect'),
            cacheTtl: const Duration(minutes: 5),
            maxCacheEntries: maxEntries,
          ),
          httpClient: MockClient((request) async {
            requestCount += 1;
            return http.Response('{"active":true,"sub":"$requestCount"}', 200);
          }),
        );

        for (final token in values) {
          await introspector.introspect(token);
        }

        final distinctTokens = values.toSet().toList(growable: false);
        final expectedRequests =
            distinctTokens.length +
            (distinctTokens.length > maxEntries ? 1 : 0);
        final retainedTokens = distinctTokens.skip(
          distinctTokens.length > maxEntries
              ? distinctTokens.length - maxEntries
              : 0,
        );
        for (final token in retainedTokens) {
          await introspector.introspect(token);
        }
        if (distinctTokens.length > maxEntries) {
          await introspector.introspect(distinctTokens.first);
        }

        expect(requestCount, equals(expectedRequests));
      }, PropertyConfig(numTests: 500, seed: 20260819));

      final result = await runner.run();
      expect(result.success, isTrue, reason: _propertyReport(result));
    },
  );
}
