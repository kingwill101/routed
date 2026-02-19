@Tags(['property'])
library;

import 'package:property_testing/property_testing.dart';
import 'package:routed/routed.dart' hide Tags;
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('RoutedRequestHandler property tests', () {
    final slugGen = Gen.oneOf(
      'abcdefghijklmnopqrstuvwxyz0123456789'.split(''),
    ).list(minLength: 1, maxLength: 10).map((chars) => chars.join());

    test('Route parameters round-trip across transports', () async {
      final runner = PropertyTestRunner<String>(slugGen, (slug) async {
        final engine = Engine()
          ..get('/echo/{value}', (ctx) async {
            ctx.json({'value': ctx.params['value']});
          });

        await engine.initialize();
        final handler = RoutedRequestHandler(engine);

        try {
          for (final mode in TransportMode.values) {
            final client = mode == TransportMode.inMemory
                ? TestClient.inMemory(handler)
                : TestClient.ephemeralServer(handler);
            try {
              final response = await client.get('/echo/$slug');
              response
                  .assertStatus(HttpStatus.ok)
                  .assertHeaderContains(
                    HttpHeaders.contentTypeHeader,
                    'application/json',
                  );
              final payload = (response.json() as Map).cast<String, dynamic>();
              expect(payload['value'], equals(slug));
            } finally {
              await client.close();
            }
          }
        } finally {
          await handler.close();
          await engine.close();
        }
      }, PropertyConfig(numTests: 20, seed: 20250314));

      final result = await runner.run();
      expect(result.success, isTrue, reason: result.report);
    });
  });
}
