import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

Future<void> main() async {
  final engine = Engine()
    ..get('/hello', (EngineContext ctx) {
      ctx.string('world');
    });

  final handler = RoutedRequestHandler(engine);

  // Standalone test using serverTest.
  serverTest('GET /hello returns world', (client, h) async {
    final response = await client.get('/hello');
    response.assertStatus(200).assertBodyContains('world');
  }, handler: handler);

  // Grouped tests using engineGroup — shares an engine across tests.
  engineGroup(
    'hello endpoint',
    engine: engine,
    define: (engine, client, engineTest) {
      engineTest('returns world', (engine, client) async {
        final response = await client.get('/hello');
        response.assertStatus(200).assertBodyContains('world');
      });

      engineTest('returns 404 for unknown path', (engine, client) async {
        final response = await client.get('/unknown');
        response.assertStatus(404);
      });
    },
  );
}
