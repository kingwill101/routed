import 'package:routed/routed.dart';
import 'package:routed/src/engine/middleware_registry.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import '../test_engine.dart';

void main() {
  TestClient? client;

  tearDown(() async {
    await client?.close();
  });

  test('route can exclude global middleware by name', () async {
    var hits = 0;
    final engine = testEngine();
    final registry = engine.container.get<MiddlewareRegistry>();
    registry.register('test.global', (_) {
      return (ctx, next) async {
        hits += 1;
        return await next();
      };
    });

    engine.middlewares = [MiddlewareRef.of('test.global')];

    engine.get('/skip', (ctx) => ctx.string('ok')).withoutMiddleware([
      'test.global',
    ]);
    engine.get('/use', (ctx) => ctx.string('ok'));

    await engine.initialize();
    client = TestClient(RoutedRequestHandler(engine));

    addTearDown(() async {
      await engine.close();
    });

    final skip = await client!.get('/skip');
    skip.assertStatus(200);
    final use = await client!.get('/use');
    use.assertStatus(200);

    expect(hits, equals(1));
  });

  test('group exclusions remove group middleware for all routes', () async {
    var hits = 0;
    final engine = testEngine();
    final registry = engine.container.get<MiddlewareRegistry>();
    registry.register('test.group', (_) {
      return (ctx, next) async {
        hits += 1;
        return await next();
      };
    });

    final group = engine.group(
      path: '/api',
      middlewares: [MiddlewareRef.of('test.group')],
      builder: (api) {
        api.get('/one', (ctx) => ctx.string('ok'));
        api.get('/two', (ctx) => ctx.string('ok'));
      },
    );

    group.withoutMiddleware(['test.group']);

    await engine.initialize();
    client = TestClient(RoutedRequestHandler(engine));

    addTearDown(() async {
      await engine.close();
    });

    final first = await client!.get('/api/one');
    first.assertStatus(200);
    final second = await client!.get('/api/two');
    second.assertStatus(200);

    expect(hits, equals(0));
  });

  test('route can exclude middleware instances', () async {
    var hits = 0;
    final engine = testEngine();

    Future<Response> custom(EngineContext ctx, Next next) async {
      hits += 1;
      return await next();
    }

    engine.get(
      '/custom',
      (ctx) => ctx.string('ok'),
      middlewares: [custom],
    ).withoutMiddleware([custom]);

    await engine.initialize();
    client = TestClient(RoutedRequestHandler(engine));

    addTearDown(() async {
      await engine.close();
    });

    final response = await client!.get('/custom');
    response.assertStatus(200);

    expect(hits, equals(0));
  });
}
