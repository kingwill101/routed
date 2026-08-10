import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'package:test/test.dart';

import 'package:{{{routed:packageName}}}/app.dart' as app;

void main() {
  group('API', () {
    late TestClient client;

    setUpAll(() async {
      final engine = await app.createEngine();
      client = TestClient(RoutedRequestHandler(engine));
    });

    tearDownAll(() async {
      await client.close();
    });

    test('lists users', () async {
      final response = await client.get('/api/v1/users');
      response.assertStatus(200).assertJson((json) {
        json.has('data').etc();
      });
    });
  });
}
