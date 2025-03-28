import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

Future<void> main() async {
  Engine engine = Engine()
    ..get("/hell", (c) {
      c.string("world");
    });

  final handler = RoutedRequestHandler(engine);
  serverTest('GET /hello returns world', (client, h) async {
    final response = await client.get('/hello');
    response.assertStatus(200).assertBodyContains("world");
  }, handler: handler);
}
