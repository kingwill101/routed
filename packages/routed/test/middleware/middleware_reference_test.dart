import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import '../test_engine.dart';

void main() {
  TestClient? client;

  tearDown(() async {
    await client?.close();
  });

  group('Middleware references', () {
    test(
      'resolve to registered middleware for mounts, groups, and routes',
      () async {
        final engine = testEngine();
        final registry = engine.container.get<MiddlewareRegistry>();

        registry
          ..register(
            'mount',
            (_) => (ctx, next) async {
              ctx.response.addHeader('x-mount', 'hit');
              return await next();
            },
          )
          ..register(
            'group',
            (_) => (ctx, next) async {
              ctx.response.addHeader('x-group', 'hit');
              return await next();
            },
          )
          ..register(
            'route',
            (_) => (ctx, next) async {
              ctx.response.addHeader('x-route', 'hit');
              return await next();
            },
          );

        final router = Router(middlewares: [MiddlewareRef.of('group')])
          ..get(
            '/named',
            (ctx) => ctx.string('ok'),
            middlewares: [MiddlewareRef.of('route')],
          );

        engine.use(router, middlewares: [MiddlewareRef.of('mount')]);

        await engine.initialize();

        final routes = engine.getAllRoutes();
        final namedRoute = routes.firstWhere(
          (route) => route.path.endsWith('/named'),
        );
        expect(
          namedRoute.middlewares.where(
            (mw) => MiddlewareReference.lookup(mw) != null,
          ),
          isEmpty,
        );

        client = TestClient(RoutedRequestHandler(engine));
        final response = await client!.get('/named');
        response
          ..assertStatus(HttpStatus.ok)
          ..assertHeader('x-mount', 'hit')
          ..assertHeader('x-group', 'hit')
          ..assertHeader('x-route', 'hit');
      },
    );

    test('throws descriptive error for unknown middleware reference', () async {
      final engine = testEngine()
        ..get(
          '/oops',
          (ctx) => ctx.string('ok'),
          middlewares: [MiddlewareRef.of('does.not.exist')],
        );

      await expectLater(
        () => engine.getAllRoutes(),
        throwsA(
          isA<StateError>().having(
            (err) => err.message,
            'message',
            contains('does.not.exist'),
          ),
        ),
      );
    });
  });
}
