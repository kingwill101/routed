// test/my_router_test.dart
import 'package:routed/src/context/context.dart';
import 'package:routed/src/engine/engine.dart';
import 'package:routed/src/router/router.dart';
import 'package:routed/src/websocket/websocket_handler.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

import '../test_helpers.dart';

void main() {
  group('MyRouter Tests', () {
    test('Produces correct paths and names', () {
      final router = Router();

      router
          .group(
            path: '/api',
            builder: (apiGroup) {
              apiGroup
                  .group(
                    path: '/books/',
                    builder: (booksGroup) {
                      // ignore: unnecessary_lambdas

                      booksGroup.get('/', (c) {}).name('list');
                    },
                  )
                  .name('books');

              apiGroup.get('/health', (c) {}).name('health.check');

              apiGroup
                  .group(
                    path: '/users/',
                    builder: (usersGroup) {
                      usersGroup.get('/', (c) {}).name('list');
                    },
                  )
                  .name('users');
            },
          )
          .name('api');

      router.build();

      final allRoutes = router.getAllRoutes();
      expect(allRoutes, hasLength(3));

      // sort by path so we can check them in a predictable order
      allRoutes.sort((a, b) => a.path.compareTo(b.path));

      // 1) /api/books/
      expect(allRoutes[0].path, equals('/api/books/'));
      expect(allRoutes[0].name, equals('api.books.list'));

      // 2) /api/health
      expect(allRoutes[1].path, equals('/api/health'));
      expect(allRoutes[1].name, equals('api.health.check'));

      // 3) /api/users/
      expect(allRoutes[2].path, equals('/api/users/'));
      expect(allRoutes[2].name, equals('api.users.list'));
    });
  });

  group('Router Tests', () {
    test('Basic route registration and name merging', () {
      final router = Router(groupName: 'api', path: '/base');

      // /base/health => name "api.health"
      router.get('/health', (c) {}).name('health');

      router.build();

      final routes = router.getAllRoutes();
      expect(routes.length, 1);

      final r = routes.first;
      expect(r.method, 'GET');
      expect(r.path, '/base/health');
      expect(r.name, 'api.health');
    });

    test('Group-level middlewares + route-level middlewares merge properly', () {
      final log = <String>[];

      // Construct a router with a group-level middleware
      final groupMW1 = makeMiddleware('GroupMW1', log);
      final groupMW2 = makeMiddleware('GroupMW2', log);

      final router = Router(
        groupName: 'test',
        path: '/test',
        middlewares: [groupMW1],
      );

      // Sub-group => inherits router-level MW, adds one more
      router
          .group(
            path: '/sub',
            middlewares: [groupMW2],
            builder: (sub) {
              sub
                  .get('/route', (c) {
                    // ...
                  }, middlewares: [makeMiddleware('RouteMW', log)])
                  .name('subroute');
            },
          )
          .name('subgroup');

      router.build();

      final allRoutes = router.getAllRoutes();
      expect(allRoutes.length, 1);

      final route = allRoutes.first;
      expect(route.path, '/test/sub/route');
      expect(route.name, 'test.subgroup.subroute');

      // The final middlewares should be [groupMW1, groupMW2, RouteMW]
      // (because the sub-group inherited from the parent, then we add route-level)
      final names = route.finalMiddlewares
          .map((mw) => middlewareLabel(mw, log))
          .toList();
      expect(names, equals(['GroupMW1', 'GroupMW2', 'RouteMW']));
    });
  });

  test('Mount multiple routers with engine-level middlewares', () {
    final log = <String>[];

    // 1) Router #1
    final router1 = Router(
      groupName: 'v1',
      path: '/r1',
      middlewares: [makeMiddleware('Router1-MW1', log)],
    );
    // e.g. /r1/health
    router1
        .get(
          '/health',
          (c) {},
          middlewares: [makeMiddleware('RouteMW-health', log)],
        )
        .name('health');

    // 2) Router #2
    final router2 = Router(groupName: 'v2', path: '/r2');
    router2
        .post(
          '/create',
          (c) {},
          middlewares: [makeMiddleware('RouteMW-create', log)],
        )
        .name('create');

    final engine = Engine();

    final engineMW1 = makeMiddleware('Engine-MW1', log);
    final engineMW2 = makeMiddleware('Engine-MW2', log);

    // Mount router1 at /api/v1
    engine.use(prefix: '/api/v1', router1, middlewares: [engineMW1]);
    // Mount router2 at /api/v2
    engine.use(prefix: '/api/v2', router2, middlewares: [engineMW2]);

    final engineRoutes = engine.getAllRoutes();
    expect(engineRoutes.length, 2);

    // Let's find the route from router1 => /api/v1/r1/health
    final healthRoute = engineRoutes.firstWhere(
      (r) => r.method == 'GET' && r.path.endsWith('health'),
    );
    expect(healthRoute.path, '/api/v1/r1/health');
    expect(healthRoute.name, 'v1.health');

    // The final middlewares = engine-level MW + router1 group-level MW + route MW
    // => [Engine-MW1, Router1-MW1, RouteMW-health]
    final healthMWNames = healthRoute.middlewares.map(
      (mw) => middlewareLabel(mw, log),
    );
    expect(
      healthMWNames,
      containsAll(['Engine-MW1', 'Router1-MW1', 'RouteMW-health']),
    );

    // Now router2 => /api/v2/r2/create
    final createRoute = engineRoutes.firstWhere(
      (r) => r.method == 'POST' && r.path.endsWith('create'),
    );
    expect(createRoute.path, '/api/v2/r2/create');
    expect(createRoute.name, 'v2.create');

    // The final middlewares = [Engine-MW2] + (any group-level from router2) + route-level
    // Router2 had no group-level MW, so final => [Engine-MW2, RouteMW-create]
    final createMWNames = createRoute.middlewares.map(
      (mw) => middlewareLabel(mw, log),
    );
    expect(createMWNames, containsAll(['Engine-MW2', 'RouteMW-create']));
  });

  test('Engine merging route-group middlewares from subgroups', () {
    final log = <String>[];

    // Build a more complex router with nested groups
    final router3 = Router(
      groupName: 'v3',
      path: '/r3',
      middlewares: [makeMiddleware('Router3-GMW', log)],
    );

    // /r3/admin => name => v3.admin
    router3
        .group(
          path: '/admin',
          middlewares: [makeMiddleware('AdminGroup-MW', log)],
          builder: (adminGroup) {
            adminGroup
                .delete(
                  '/user',
                  (c) {},
                  middlewares: [makeMiddleware('DeleteUser-MW', log)],
                )
                .name('deleteUser');
          },
        )
        .name('admin');

    final engine = Engine();
    engine.use(
      prefix: '/api/v3',
      router3,
      middlewares: [makeMiddleware('EngineMW-forRouter3', log)],
    );

    final finalRoutes = engine.getAllRoutes();
    expect(finalRoutes.length, 1);

    final r = finalRoutes.first;
    // path => /api/v3/r3/admin/user
    expect(r.path, '/api/v3/r3/admin/user');
    // name => v3.admin.deleteUser
    expect(r.name, 'v3.admin.deleteUser');
    expect(r.method, 'DELETE');

    // Now let's check the middlewares
    // We should have engine-level, router-level, group-level, route-level
    // in the final order: [EngineMW-forRouter3, Router3-GMW, AdminGroup-MW, DeleteUser-MW]
    final mwLabels = r.middlewares
        .map((mw) => middlewareLabel(mw, log))
        .toList();
    expect(
      mwLabels,
      equals([
        'EngineMW-forRouter3',
        'Router3-GMW',
        'AdminGroup-MW',
        'DeleteUser-MW',
      ]),
    );
  });

  group('EngineContext parameter helpers', () {
    TestClient? client;

    tearDown(() async {
      await client?.close();
    });

    test('mustGetParam returns captured route parameter', () async {
      final engine = Engine();
      engine.get('/users/{id}', (ctx) {
        final id = ctx.mustGetParam<String>('id');
        return ctx.string(id);
      });

      client = TestClient(RoutedRequestHandler(engine));
      final response = await client!.get('/users/42');

      response
        ..assertStatus(200)
        ..assertBodyEquals('42');
    });

    test('mustGetParam throws when parameter missing', () async {
      final engine = Engine();
      engine.get('/users', (ctx) {
        expect(() => ctx.mustGetParam<String>('id'), throwsStateError);
        return ctx.string('ok');
      });

      client = TestClient(RoutedRequestHandler(engine));
      final response = await client!.get('/users');

      response
        ..assertStatus(200)
        ..assertBodyEquals('ok');
    });
  });

  group('Route Constraints Tests (Engine)', () {
    test('Engine merges constraints at build time', () {
      final router = Router();
      // Here, we add constraints that limit "value" to letters only
      router.get(
        '/alpha/{value}',
        (c) {},
        constraints: {'value': r'^[A-Za-z]+$'},
      );

      final engine = Engine();
      engine.use(router);
      final routes = engine.getAllRoutes();
      expect(routes.length, 1);

      final route = routes.first;
      expect(route.constraints['value'], r'^[A-Za-z]+$');
    });

    test('Multiple constraints from multiple routes', () {
      final router = Router();
      router.get('/numeric/{id}', (c) {}, constraints: {'id': r'^\d+$'});
      router.get(
        '/alpha/{slug}',
        (c) {},
        constraints: {'slug': r'^[a-zA-Z]+$'},
      );

      final engine = Engine()..use(router);
      final routes = engine.getAllRoutes();
      expect(routes.length, 2);

      final numericRoute = routes.firstWhere(
        (r) => r.path.endsWith('numeric/{id}'),
      );
      final alphaRoute = routes.firstWhere(
        (r) => r.path.endsWith('alpha/{slug}'),
      );

      expect(numericRoute.constraints['id'], r'^\d+$');
      expect(alphaRoute.constraints['slug'], r'^[a-zA-Z]+$');
    });
  });

  test('WebSocket routes inherit prefixes and middlewares', () {
    final log = <String>[];
    final engine = Engine(middlewares: [makeMiddleware('Engine', log)]);
    final router = Router(
      path: '/api',
      middlewares: [makeMiddleware('Router', log)],
    );

    router
        .group(
          path: '/ws',
          middlewares: [makeMiddleware('Group', log)],
          builder: (group) {
            group.ws(
              '/live',
              _NoOpWebSocketHandler(),
              middlewares: [makeMiddleware('Route', log)],
            );
          },
        )
        .name('ws');

    engine.use(
      prefix: '/v1',
      router,
      middlewares: [makeMiddleware('Mount', log)],
    );

    engine.getAllRoutes();

    final route = engine.debugWebSocketRoutes['/v1/api/ws/live'];
    expect(route, isNotNull);
    final labels = route!.middlewares
        .map((mw) => middlewareLabel(mw, log))
        .toList();
    expect(labels, equals(['Mount', 'Router', 'Group', 'Route']));
  });
}

class _NoOpWebSocketHandler implements WebSocketHandler {
  @override
  Future<void> onClose(WebSocketContext context) async {}

  @override
  Future<void> onError(WebSocketContext context, dynamic error) async {}

  @override
  Future<void> onMessage(WebSocketContext context, dynamic message) async {}

  @override
  Future<void> onOpen(WebSocketContext context) async {}
}
