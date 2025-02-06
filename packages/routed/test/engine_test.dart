// test/engine_test.dart

import 'package:routed/src/engine/engine.dart';
import 'package:routed/src/router/router.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('Engine Tests', () {
    test('Mount multiple routers with engine-level middlewares', () {
      final log = <String>[];

      // 1) Router #1
      final router1 = Router(groupName: 'v1', path: '/r1', middlewares: [
        makeMiddleware('Router1-MW1', log),
      ]);
      // e.g. /r1/health
      router1.get('/health', (c) {}, middlewares: [
        makeMiddleware('RouteMW-health', log),
      ]).name('health');

      // 2) Router #2
      final router2 = Router(groupName: 'v2', path: '/r2');
      router2.post('/create', (c) {}, middlewares: [
        makeMiddleware('RouteMW-create', log),
      ]).name('create');

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
      final healthRoute = engineRoutes
          .firstWhere((r) => r.method == 'GET' && r.path.endsWith('health'));
      expect(healthRoute.path, '/api/v1/r1/health');
      expect(healthRoute.name, 'v1.health');

      // The final middlewares = engine-level MW + router1 group-level MW + route MW
      // => [Engine-MW1, Router1-MW1, RouteMW-health]
      final healthMWNames =
          healthRoute.middlewares.map((mw) => middlewareLabel(mw, log));
      expect(healthMWNames,
          containsAll(['Engine-MW1', 'Router1-MW1', 'RouteMW-health']));

      // Now router2 => /api/v2/r2/create
      final createRoute = engineRoutes
          .firstWhere((r) => r.method == 'POST' && r.path.endsWith('create'));
      expect(createRoute.path, '/api/v2/r2/create');
      expect(createRoute.name, 'v2.create');

      // The final middlewares = [Engine-MW2] + (any group-level from router2) + route-level
      // Router2 had no group-level MW, so final => [Engine-MW2, RouteMW-create]
      final createMWNames =
          createRoute.middlewares.map((mw) => middlewareLabel(mw, log));
      expect(createMWNames, containsAll(['Engine-MW2', 'RouteMW-create']));
    });

    test('Engine merging route-group middlewares from subgroups', () {
      final log = <String>[];

      // Build a more complex router with nested groups
      final router3 = Router(groupName: 'v3', path: '/r3', middlewares: [
        makeMiddleware('Router3-GMW', log),
      ]);

      // /r3/admin => name => v3.admin
      router3
          .group(
            path: '/admin',
            middlewares: [makeMiddleware('AdminGroup-MW', log)],
            builder: (adminGroup) {
              adminGroup.delete('/user', (c) {}, middlewares: [
                makeMiddleware('DeleteUser-MW', log),
              ]).name('deleteUser');
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
      final mwLabels =
          r.middlewares.map((mw) => middlewareLabel(mw, log)).toList();
      expect(
        mwLabels,
        equals([
          'EngineMW-forRouter3',
          'Router3-GMW',
          'AdminGroup-MW',
          'DeleteUser-MW'
        ]),
      );
    });

    group('Route Constraints Tests (Engine)', () {
      test('Engine merges constraints at build time', () {
        final router = Router();
        // Here, we add constraints that limit "value" to letters only
        router.get('/alpha/{value}', (c) {}, constraints: {
          'value': r'^[A-Za-z]+$',
        });

        final engine = Engine();
        engine.use(router);
        final routes = engine.getAllRoutes();
        expect(routes.length, 1);

        final route = routes.first;
        expect(route.constraints['value'], r'^[A-Za-z]+$');
      });

      test('Multiple constraints from multiple routes', () {
        final router = Router();
        router.get('/numeric/{id}', (c) {}, constraints: {
          'id': r'^\d+$',
        });
        router.get('/alpha/{slug}', (c) {}, constraints: {
          'slug': r'^[a-zA-Z]+$',
        });

        final engine = Engine()..use(router);
        final routes = engine.getAllRoutes();
        expect(routes.length, 2);

        final numericRoute =
            routes.firstWhere((r) => r.path.endsWith('numeric/{id}'));
        final alphaRoute =
            routes.firstWhere((r) => r.path.endsWith('alpha/{slug}'));

        expect(numericRoute.constraints['id'], r'^\d+$');
        expect(alphaRoute.constraints['slug'], r'^[a-zA-Z]+$');
      });
    });
  });

  group("Calling routes by name", () {
    test('Calling routes by name', () {
      final router = Router();
      router.get('/test', (c) {
        expect(c.request.path, '/test');
        expect(c.request.method, 'GET');
      }).name('test');

      // final engine = Engine()..use(router);
      // engine.
    });
  });
}
