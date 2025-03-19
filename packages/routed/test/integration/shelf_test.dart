import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:routed/src/integrations/shelf.dart';

shelf.Middleware testShelfMiddleware() {
  return (shelf.Handler innerHandler) {
    return (shelf.Request request) async {
      final shelfResponse = await innerHandler(request);
      return shelfResponse.change(headers: {'X-Shelf-Middleware': 'Applied'});
    };
  };
}

shelf.Handler testShelfHandler = (shelf.Request request) {
  return shelf.Response.ok('Hello from Shelf Handler',
      headers: {'Content-Type': 'text/plain'});
};

void main() {
  group('Engine Tests', () {
    // Existing engine tests ...

    group('Shelf Integration Tests', () {
      test('Can use Shelf middleware in Routed pipeline',
          timeout: const Timeout(Duration(seconds: 120)), () async {
        final engine = Engine();
        final router = Router();

        router.get(
            '/shelf-middleware', fromShelfMiddleware(testShelfMiddleware()));

        engine.use(router);
        final client = TestClient(RoutedRequestHandler(engine),
            mode: TransportMode.ephemeralServer);

        final response = await client.get('/shelf-middleware');
        response
          ..assertStatus(200)
          ..assertHeader('X-Shelf-Middleware', 'Applied');
      });

      test('Can use Shelf handler in Routed route', () async {
        final engine = Engine();
        final router = Router();

        router.get('/shelf-handler', fromShelfHandler(testShelfHandler));

        engine.use(router);
        final client = TestClient(RoutedRequestHandler(engine),
            mode: TransportMode.ephemeralServer);

        final response = await client.get('/shelf-handler');
        response
          ..assertStatus(200)
          ..assertBodyEquals('Hello from Shelf Handler')
          ..assertHeaderContains('Content-Type', 'text/plain');
      });
    }, skip: 'Shelf integration tests are skipped');
  });
}
