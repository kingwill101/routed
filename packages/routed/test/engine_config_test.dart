import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:test/test.dart';

void main() {
  late EngineTestClient client;

  tearDown(() async {
    await client.close();
  });

  group('Engine Configuration Tests', () {
    group('RedirectTrailingSlash', () {
      test('enabled - redirects GET requests with 301', () async {
        final engine =
            Engine(config: EngineConfig(redirectTrailingSlash: true));
        final router = Router();
        router.get('/users', (ctx) => ctx.string('users'));
        engine.use(router);

        client = EngineTestClient(engine);
        final response = await client.get('/users/');
        response
          ..assertStatus(301)
          ..assertHeader('Location', '/users');
      });

      test('enabled - redirects POST requests with 307', () async {
        final engine =
            Engine(config: EngineConfig(redirectTrailingSlash: true));
        final router = Router();
        router.post('/users', (ctx) => ctx.string('created'));
        engine.use(router);

        client = EngineTestClient(engine);
        final response = await client.post('/users/', null);
        response
          ..assertStatus(307)
          ..assertHeader('Location', '/users');
      });

      test('disabled - returns 404 for trailing slash', () async {
        final engine =
            Engine(config: EngineConfig(redirectTrailingSlash: false));
        final router = Router();
        router.get('/users', (ctx) => ctx.string('users'));
        engine.use(router);

        client = EngineTestClient(engine);
        final response = await client.get('/users/');
        response.assertStatus(404);
      });
    });

    group('HandleMethodNotAllowed', () {
      test('enabled - returns 405 with Allow header', () async {
        final engine =
            Engine(config: EngineConfig(handleMethodNotAllowed: true));
        final router = Router();
        router.get('/users', (ctx) => ctx.string('users'));
        router.post('/users', (ctx) => ctx.string('created'));
        engine.use(router);

        client = EngineTestClient(engine);
        final response = await client.put('/users', null);
        response
          ..assertStatus(405)
          ..assertHeaderContains('Allow', ['GET', 'POST']);
      });

      test('disabled - returns 404 for wrong method', () async {
        final engine =
            Engine(config: EngineConfig(handleMethodNotAllowed: false));
        final router = Router();
        router.get('/users', (ctx) => ctx.string('users'));
        engine.use(router);

        client = EngineTestClient(engine);
        final response = await client.post('/users', null);
        response.assertStatus(404);
      });
    });

    group('ForwardedByClientIP', () {
      test('processes X-Forwarded-For header', () async {
        final engine = Engine(
            config: EngineConfig(
                forwardedByClientIP: true,
                remoteIPHeaders: ['X-Forwarded-For']));
        final router = Router();
        router.get('/ip', (ctx) => ctx.string(ctx.request.ip));
        engine.use(router);

        client = EngineTestClient(engine);
        final response = await client.get('/ip', headers: {
          'X-Forwarded-For': ['1.2.3.4']
        });
        response
          ..assertStatus(200)
          ..assertBodyEquals('1.2.3.4');
      });

      test('processes X-Real-IP header', () async {
        final engine = Engine(
            config: EngineConfig(
                forwardedByClientIP: true, remoteIPHeaders: ['X-Real-IP']));
        final router = Router();
        router.get('/ip', (ctx) => ctx.string(ctx.request.ip));
        engine.use(router);

        client = EngineTestClient(engine);
        final response = await client.get('/ip', headers: {
          'X-Real-IP': ['5.6.7.8']
        });
        response.assertBodyEquals('5.6.7.8');
      });
    });

    group('Combined Configuration', () {
      test('multiple options work together', () async {
        final engine = Engine(
            config: EngineConfig(
                redirectTrailingSlash: true,
                handleMethodNotAllowed: true,
                forwardedByClientIP: true,
                remoteIPHeaders: ['X-Real-IP']));
        final router = Router();
        router.get('/users', (ctx) => ctx.string('users'));
        router.get('/ip', (ctx) => ctx.string(ctx.request.ip));

        engine.use(router);

        client = EngineTestClient(engine);

        // Test trailing slash redirect
        var response = await client.get('/users/');
        response
          ..assertStatus(301)
          ..assertHeader('Location', '/users');

        // Test method not allowed
        response = await client.post('/users', null);
        response
          ..assertStatus(405)
          ..assertHeaderContains('Allow', ['GET']);

        // Test IP forwarding
        response = await client.get('/ip', headers: {
          'X-Real-IP': ['1.2.3.4']
        });
        response.assertBodyEquals('1.2.3.4');

        // Test normal request
        response = await client.get('/users');
        response
          ..assertStatus(200)
          ..assertBodyEquals('users');
      });
    });
  });
}
