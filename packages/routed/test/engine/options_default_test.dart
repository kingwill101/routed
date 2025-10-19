import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('Default OPTIONS handler', () {
    late Engine engine;
    late TestClient client;

    setUp(() async {
      engine = Engine();
      engine
        ..get('/items', (ctx) => ctx.string('index'))
        ..post('/items', (ctx) => ctx.string('created'));

      await engine.initialize();

      client = TestClient(
        RoutedRequestHandler(engine),
        mode: TransportMode.ephemeralServer,
      );
    });

    tearDown(() async {
      await client.close();
      await engine.close();
    });

    test('returns allowed methods when OPTIONS not registered', () async {
      final response = await client.options('/items');
      response.assertStatus(HttpStatus.noContent);
      expect(
        response.headers[HttpHeaders.allowHeader]?.first,
        equals('GET, HEAD, OPTIONS, POST'),
      );
    });

    test('continues to method not allowed when OPTIONS disabled', () async {
      engine.updateConfig(engine.config.copyWith(defaultOptionsEnabled: false));

      final response = await client.options('/items');

      response.assertStatus(HttpStatus.methodNotAllowed);
      expect(
        response.headers[HttpHeaders.allowHeader]?.first,
        equals('GET, HEAD, OPTIONS, POST'),
      );
    });
  });
}
