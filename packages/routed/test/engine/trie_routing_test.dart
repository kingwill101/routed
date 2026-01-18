
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  test('trie routing prefers static paths and matches params', () async {
    final engine = Engine(
      config: EngineConfig(
        features: const EngineFeatures(enableTrieRouting: true),
      ),
    );

    engine.get('/users/me', (ctx) => ctx.string('static'));
    engine.get('/users/{id}', (ctx) {
      return ctx.string('user:${ctx.params['id']}');
    });

    final client = TestClient.inMemory(RoutedRequestHandler(engine));
    addTearDown(() async {
      await client.close();
      await engine.close();
    });

    final me = await client.get('/users/me');
    me
      ..assertStatus(HttpStatus.ok)
      ..assertBodyEquals('static');

    final user = await client.get('/users/42');
    user
      ..assertStatus(HttpStatus.ok)
      ..assertBodyEquals('user:42');
  });
}
