import 'package:property_testing/property_testing.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

import 'test_helpers.dart';
import 'test_engine.dart';

void main() {
  group('Route Matching Tests', () {
    /// Test suite for verifying route matching and HTTP method handling in the routing engine
    ///
    /// This test group focuses on two key scenarios:
    /// 1. Ensuring routes can be matched for all standard HTTP methods
    /// 2. Verifying that unmatched routes return a 404 status code
    ///
    /// The tests demonstrate:
    /// - Dynamic route registration for multiple HTTP methods
    /// - Consistent response handling across different HTTP methods
    /// - Proper 404 error handling for non-existent routes
    ///
    /// Key test cases:
    /// - [test('Single route match works for various HTTP methods')]:
    ///   Validates route matching for GET, POST, PUT, PATCH, HEAD,
    ///   OPTIONS, DELETE, CONNECT, and TRACE methods
    /// - [test('Route mismatch returns 404')]:
    ///   Confirms that requests to undefined routes result in a 404 status
    ///
    /// @see Engine
    /// @see RoutedRequestHandler
    /// @see TestClient
    test('routes respond across random HTTP verb sets (property)', () async {
      final runner = PropertyTestRunner<Set<String>>(httpMethodSet(), (
        methods,
      ) async {
        final engine = testEngine();
        for (final method in methods) {
          engine.handle(method, '/test', (ctx) => ctx.string(method));
        }

        final localClient = TestClient(RoutedRequestHandler(engine));
        for (final method in methods) {
          final response = await localClient.request(method, '/test');
          response.assertStatus(200);
          if (method != 'HEAD') {
            response.assertBodyEquals(method);
          }
        }

        await localClient.close();
        await engine.close();
      }, PropertyConfig(numTests: 30, seed: 20250311));

      final result = await runner.run();
      expect(result.success, isTrue, reason: result.report);
    });

    test('Route mismatch returns 404', () async {
      final engine = testEngine();

      // Define a single POST route
      engine.post('/test_2', (ctx) => ctx.string('post ok'));

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);
      addTearDown(engine.close);

      final response = await client.get('/test');
      response.assertStatus(404);
    });
  });

  group('Trailing Slash Redirect Tests', () {
    test('Redirects for trailing slashes with 301 or 307', () async {
      final engine = testEngine(
        routingConfig: const RoutingConfig(redirectTrailingSlash: true),
      );

      engine.get('/path', (ctx) => ctx.string('get ok'));
      engine.post('/path2', (ctx) => ctx.string('post ok'));

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);
      addTearDown(engine.close);

      // Test trailing slash redirects
      var response = await client.get('/path/');
      response
        ..assertStatus(301)
        ..assertHeader('Location', '/path');

      response = await client.post('/path2/', null);
      response
        ..assertStatus(307)
        ..assertHeader('Location', '/path2');
    });

    test('Disables trailing slash redirects when configured', () async {
      final engine = testEngine(
        routingConfig: const RoutingConfig(redirectTrailingSlash: false),
      );

      engine.get('/path', (ctx) => ctx.string('ok'));

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);
      addTearDown(engine.close);

      final response = await client.get('/path/');
      response.assertStatus(404);
    });
  });

  group('Path Parameters Tests', () {
    test('Correctly parses path parameters', () async {
      final engine = testEngine();

      engine.get('/test/{name}/{last_name}/{*wild}', (ctx) {
        final params = ctx.params;
        ctx.json({
          'name': params['name'],
          'last_name': params['last_name'],
          'wild': params['wild'],
        });
      });

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);
      addTearDown(engine.close);

      final response = await client.get('/test/john/smith/is/super/great');
      response
        ..assertStatus(200)
        ..assertJsonContains({
          'name': 'john',
          'last_name': 'smith',
          'wild': 'is/super/great',
        });
    });
  });

  group('Method Not Allowed Tests', () {
    test('Returns 405 with allowed methods when enabled', () async {
      final engine = testEngine(
        routingConfig: const RoutingConfig(handleMethodNotAllowed: true),
      );

      engine.get('/path', (ctx) => ctx.string('get ok'));
      engine.post('/path', (ctx) => ctx.string('post ok'));

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);
      addTearDown(engine.close);

      final response = await client.put('/path', null);
      response
        ..assertStatus(405)
        ..assertHeaderContains('Allow', ['GET', 'POST']);
    });

    test('Returns 404 for wrong methods when disabled', () async {
      final engine = testEngine(
        routingConfig: const RoutingConfig(handleMethodNotAllowed: false),
      );

      engine.post('/path', (ctx) => ctx.string('post ok'));

      final client = TestClient(RoutedRequestHandler(engine));
      addTearDown(client.close);
      addTearDown(engine.close);

      final response = await client.get('/path');
      response.assertStatus(404);
    });
  });
}
