import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

import 'package:full_stack/app.dart' as app;

void main() {
  test('GET /api/todos returns seeded data', () async {
    final engine = await app.createEngine();
    final client = TestClient(RoutedRequestHandler(engine));

    final response = await client.get('/api/todos');
    response.assertStatus(200);
    final json = response.json() as Map<String, dynamic>;
    expect(json['data'], isA<List>());
    expect(json['data'], isNotEmpty);

    await client.close();
  });
}
