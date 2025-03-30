import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('Fallback Route Tests', () {
    late TestClient client;
    late Engine engine;

    setUp(() {
      engine = Engine();
      client = TestClient.inMemory(RoutedRequestHandler(engine));
    });

    tearDown(() async {
      await client.close();
    });

    test('Global fallback route handles unmatched requests', () async {
      // Regular route
      engine.get('/hello', (ctx) => ctx.string('Hello, World!'));

      // Global fallback
      engine.fallback((ctx) {
        return ctx.string('Fallback: ${ctx.uri.path}');
      });

      // Test existing route
      var response = await client.get('/hello');
      response
        ..assertStatus(200)
        ..assertBodyEquals('Hello, World!');

      // Test unmatched route
      response = await client.get('/nonexistent');
      response
        ..assertStatus(200)
        ..assertBodyEquals('Fallback: /nonexistent');
    });

    test('Group-specific fallback routes', () async {
      engine.group(
        path: '/api/v1',
        builder: (router) {
          // Regular API route
          router.get('/users', (ctx) => ctx.json({'users': <Object>[]}));

          // API-specific fallback
          router.fallback((ctx) {
            return ctx.json({
              'error': 'API endpoint not found',
              'version': 'v1',
              'path': ctx.uri.path,
            });
          });
        },
      );

      // Test existing API route
      var response = await client.get('/api/v1/users');
      response
        ..assertStatus(200)
        ..assertJson((json) => json.where('users', <Object>[]));

      // Test unmatched API route
      response = await client.get('/api/v1/nonexistent');
      response
        ..assertStatus(200)
        ..assertJson((json) {
          json
              .where('error', 'API endpoint not found')
              .where('version', 'v1')
              .where('path', '/api/v1/nonexistent');
        });
    });

    test('Fallback route with middleware', () async {
      int middlewareCalled = 0;

      engine.group(
        path: '/secured',
        middlewares: [
          (ctx) async {
            middlewareCalled++;
            await ctx.next();
          },
        ],
        builder: (router) {
          router.fallback((ctx) => ctx.json({
                'error': 'Secured route not found',
                'path': ctx.uri.path,
              }));
        },
      );

      final response = await client.get('/secured/nonexistent');
      response
        ..assertStatus(200)
        ..assertJson((json) {
          json
              .where('error', 'Secured route not found')
              .where('path', '/secured/nonexistent');
        });

      expect(middlewareCalled, equals(1));
    });

    test('Multiple group fallbacks use most specific match', () async {
      engine.group(
        path: '/api',
        builder: (api) {
          // General API fallback
          api.fallback((ctx) => ctx.json({
                'error': 'API route not found',
                'scope': 'api',
                'path': ctx.uri.path,
              }));

          api.group(
            path: '/v1',
            builder: (v1) {
              // V1-specific fallback
              v1.fallback((ctx) => ctx.json({
                    'error': 'V1 API route not found',
                    'scope': 'v1',
                    'path': ctx.uri.path,
                  }));
            },
          );
        },
      );

      // Test V1 fallback
      var response = await client.get('/api/v1/nonexistent');
      response
        ..assertStatus(200)
        ..assertJson((json) {
          json
              .where('error', 'V1 API route not found')
              .where('scope', 'v1')
              .where('path', '/api/v1/nonexistent');
        });

      // Test general API fallback
      // response = await client.get('/api/nonexistent');
      // response
      //   ..assertStatus(200)
      //   ..assertJson((json) {
      //     json
      //         .where('error', 'API route not found')
      //         .where('scope', 'api')
      //         .where('path', '/api/nonexistent');
      //   });
    });
  });
}
