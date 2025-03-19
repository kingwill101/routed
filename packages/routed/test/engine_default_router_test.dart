// test/engine_default_router_test.dart

import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  group('Engine Default Router Tests', () {
    late TestClient client;
    late Engine engine;

    setUp(() {
      engine = Engine();
      client = TestClient.inMemory(RoutedRequestHandler(engine));
    });

    tearDown(() async {
      await client.close();
    });

    test('Routes registered directly on Engine are accessible', () async {
      // Register routes directly on the Engine
      engine.get('/hello', (ctx) => ctx.string('Hello, World!'));
      engine.post('/echo', (ctx) async {
        final body = await ctx.request.body();
        ctx.string('Echo: $body');
      });

      // Test GET /hello
      var response = await client.get('/hello');
      response
        ..assertStatus(200)
        ..assertBodyEquals('Hello, World!');

      // Test POST /echo
      response = await client.post('/echo', 'Test Body');
      response
        ..assertStatus(200)
        ..assertBodyEquals('Echo: Test Body');
    });

    test('Default router is used when no other routers are mounted', () async {
      // We have not called engine.use() to mount any routers

      // Register a route on the default router
      engine.get('/default', (ctx) => ctx.string('Default Route'));

      // Test GET /default
      var response = await client.get('/default');
      response
        ..assertStatus(200)
        ..assertBodyEquals('Default Route');

      // Ensure that a route not defined returns 404
      response = await client.get('/not-found');
      response.assertStatus(404);
    });

    test('Can apply middlewares to the Engine directly', () async {
      // Apply a middleware to the engine
      engine.middlewares.add((ctx) async {
        ctx.setHeader('X-Engine-Middleware', 'Active');
        await ctx.next();
      });

      // Register a route
      engine.get('/middleware', (ctx) => ctx.string('Middleware Test'));

      // Test GET /middleware
      var response = await client.get('/middleware');
      response
        ..assertStatus(200)
        ..assertBodyEquals('Middleware Test')
        ..assertHeader('X-Engine-Middleware', 'Active');
    });

    test('RouteBuilder allows setting name and creating groups', () async {
      // Register a route and set its name
      engine.get('/users', (ctx) => ctx.string('User List')).name('users.list');
      engine.group(
          path: '/users',
          builder: (router) {
            router.get('/{userId:int}', (ctx) {
              final userId = ctx.param('userId');
              ctx.string('User Details for $userId');
            }).name('users.details');

            router.put('/{userId:int}', (ctx) {
              final userId = ctx.param('userId');
              ctx.string('Update User $userId');
            }).name('users.update');
          });
      // Test GET /users
      var response = await client.get('/users');
      response
        ..assertStatus(200)
        ..assertBodyEquals('User List');

      // Test GET /users/123
      response = await client.get('/users/123');
      response
        ..assertStatus(200)
        ..assertBodyEquals('User Details for 123');

      // Test PUT /users/123
      response = await client.put('/users/123', null);
      response
        ..assertStatus(200)
        ..assertBodyEquals('Update User 123');
    });
  });
}
