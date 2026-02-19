import 'dart:async';

import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

/// A simple controller for testing.
class GreetingController extends Controller {
  GreetingController() : super(prefix: '/greetings', name: 'greetings');

  @override
  void routes() {
    router.get('/', _index);
    router.get('/{name}', _show);
    router.post('/', _store);
  }

  FutureOr<dynamic> _index(EngineContext ctx) {
    return ctx.json({
      'greetings': ['hello', 'hi', 'hey'],
    });
  }

  FutureOr<dynamic> _show(EngineContext ctx) {
    final name = ctx.param('name');
    return ctx.string('Hello, $name!');
  }

  FutureOr<dynamic> _store(EngineContext ctx) async {
    return ctx.json({'created': true});
  }
}

/// Controller with middlewares.
class AuthedController extends Controller {
  static int middlewareCallCount = 0;

  AuthedController()
    : super(
        prefix: '/admin',
        name: 'admin',
        middlewares: [
          (ctx, next) {
            middlewareCallCount++;
            ctx.setHeader('X-Admin-Middleware', 'applied');
            return next();
          },
        ],
      );

  @override
  void routes() {
    router.get('/dashboard', _dashboard);
  }

  FutureOr<dynamic> _dashboard(EngineContext ctx) {
    return ctx.string('Admin dashboard');
  }
}

/// Minimal controller with no routes override.
class EmptyController extends Controller {
  EmptyController() : super(prefix: '/empty');
}

void main() {
  group('Controller', () {
    test('constructor calls routes() and registers on internal router', () {
      final ctrl = GreetingController();
      final routes = ctrl.router.getAllRoutes();
      expect(routes, hasLength(3));
    });

    test('prefix and name are stored', () {
      final ctrl = GreetingController();
      expect(ctrl.prefix, '/greetings');
      expect(ctrl.name, 'greetings');
    });

    test('middlewares are stored', () {
      final ctrl = AuthedController();
      expect(ctrl.middlewares, hasLength(1));
    });

    test('call() returns the internal router', () {
      final ctrl = GreetingController();
      expect(ctrl(), same(ctrl.router));
    });

    test('empty controller has no routes', () {
      final ctrl = EmptyController();
      final routes = ctrl.router.getAllRoutes();
      expect(routes, isEmpty);
      expect(ctrl.prefix, '/empty');
      expect(ctrl.name, isNull);
    });

    test('routes have correct methods and paths', () {
      final ctrl = GreetingController();
      final routes = ctrl.router.getAllRoutes();

      final getRoutes = routes.where((r) => r.method == 'GET').toList();
      final postRoutes = routes.where((r) => r.method == 'POST').toList();

      expect(getRoutes, hasLength(2));
      expect(postRoutes, hasLength(1));
      expect(getRoutes.any((r) => r.path == '/'), isTrue);
      expect(getRoutes.any((r) => r.path == '/{name}'), isTrue);
      expect(postRoutes.first.path, '/');
    });
  });

  group('Controller — mounted on engine', () {
    engineGroup(
      'controller integration',
      options: [
        (engine) {
          final greeting = GreetingController();
          engine.use(greeting.router, prefix: greeting.prefix);

          final admin = AuthedController();
          engine.use(
            admin.router,
            prefix: admin.prefix,
            middlewares: admin.middlewares,
          );
        },
      ],
      define: (engine, client, tess) {
        tess('GET /greetings/ returns list', (engine, client) async {
          final res = await client.getJson('/greetings/');
          res
            ..assertStatus(200)
            ..assertJson((json) {
              json.where('greetings', ['hello', 'hi', 'hey']);
            });
        });

        tess('GET /greetings/{name} returns greeting', (engine, client) async {
          final res = await client.get('/greetings/World');
          res
            ..assertStatus(200)
            ..assertBodyEquals('Hello, World!');
        });

        tess('POST /greetings/ returns created', (engine, client) async {
          final res = await client.postJson('/greetings/', <String, Object?>{});
          res
            ..assertStatus(200)
            ..assertJsonPath('created', true);
        });

        tess('controller middlewares are applied', (engine, client) async {
          AuthedController.middlewareCallCount = 0;
          final res = await client.get('/admin/dashboard');
          res
            ..assertStatus(200)
            ..assertBodyEquals('Admin dashboard')
            ..assertHasHeader('X-Admin-Middleware');
          expect(AuthedController.middlewareCallCount, 1);
        });
      },
    );
  });
}
