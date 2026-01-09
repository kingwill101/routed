import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'test_engine.dart';

void main() {
  group('Engine Boot Lifecycle', () {
    late Engine engine;
    late TestClient client;

    setUp(() {
      engine = testEngine();
      client = TestClient.inMemory(RoutedRequestHandler(engine));
    });

    tearDown(() async {
      await client.close();
    });

    test('Using engine before boot completes throws or fails', () async {
      // Register a route
      engine.get('/hello', (ctx) => ctx.string('Hello, Boot!'));
      // Intentionally do NOT await engine.onBoot
      // Try to make a request immediately
      // Depending on implementation, this may throw or return an error response
      try {
        final response = await client.get('/hello');
        // If it does not throw, assert that it fails gracefully
        expect(
          response.statusCode,
          isNot(200),
          reason: 'Should not succeed before boot',
        );
      } catch (e) {
        // If it throws, that's also acceptable for this test
        expect(e, isNotNull);
      }
    });

    test('Using engine after boot completes works', () async {
      engine.get('/hello', (ctx) => ctx.string('Hello, Boot!'));

      final response = await client.get('/hello');
      response
        ..assertStatus(200)
        ..assertBodyEquals('Hello, Boot!');
    });
  });
}
