// test/engine_test.dart

import 'package:test/test.dart';
import 'package:untitled1/untitled1.dart';    // your Engine file

void main() {
  group('Router Tests', () {
    test('Basic route registration and name merging', () {
      final router = Router(groupName: 'api', path: '/base');

      // /base/health => name "api.health"
      router.get('/health', (req, res) {}).name('health');

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
          sub.get('/route', (req, res) {
            // ...
          }, middlewares: [
            makeMiddleware('RouteMW', log)
          ]).name('subroute');
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
      final names = route.finalMiddlewares.map((mw) => _middlewareLabel(mw, log)).toList();
      expect(names, equals(['GroupMW1', 'GroupMW2', 'RouteMW']));
    });
  });

  group('Engine Tests', () {
    test('Mount multiple routers with engine-level middlewares', () {
      final log = <String>[];

      // 1) Router #1
      final router1 = Router(groupName: 'v1', path: '/r1', middlewares: [
        makeMiddleware('Router1-MW1', log),
      ]);
      // e.g. /r1/health
      router1.get('/health', (req, res) {}, middlewares: [
        makeMiddleware('RouteMW-health', log),
      ]).name('health');

      // 2) Router #2
      final router2 = Router(groupName: 'v2', path: '/r2');
      router2.post('/create', (req, res) {}, middlewares: [
        makeMiddleware('RouteMW-create', log),
      ]).name('create');

      final engine = Engine();

      final engineMW1 = makeMiddleware('Engine-MW1', log);
      final engineMW2 = makeMiddleware('Engine-MW2', log);

      // Mount router1 at /api/v1
      engine.use('/api/v1', router1, middlewares: [engineMW1]);
      // Mount router2 at /api/v2
      engine.use('/api/v2', router2, middlewares: [engineMW2]);

      // Build engine
      engine.build();

      final engineRoutes = engine.getAllRoutes();
      expect(engineRoutes.length, 2);

      // Let's find the route from router1 => /api/v1/r1/health
      final healthRoute = engineRoutes
          .firstWhere((r) => r.method == 'GET' && r.path.endsWith('health'));
      expect(healthRoute.path, '/api/v1/r1/health');
      expect(healthRoute.name, 'v1.health');

      // The final middlewares = engine-level MW + router1 group-level MW + route MW
      // => [Engine-MW1, Router1-MW1, RouteMW-health]
      final healthMWNames = healthRoute.middlewares.map((mw) => _middlewareLabel(mw, log));
      expect(healthMWNames, containsAll(['Engine-MW1', 'Router1-MW1', 'RouteMW-health']));

      // Now router2 => /api/v2/r2/create
      final createRoute = engineRoutes
          .firstWhere((r) => r.method == 'POST' && r.path.endsWith('create'));
      expect(createRoute.path, '/api/v2/r2/create');
      expect(createRoute.name, 'v2.create');

      // The final middlewares = [Engine-MW2] + (any group-level from router2) + route-level
      // Router2 had no group-level MW, so final => [Engine-MW2, RouteMW-create]
      final createMWNames = createRoute.middlewares.map((mw) => _middlewareLabel(mw, log));
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
          adminGroup.delete('/user', (req, res) {}, middlewares: [
            makeMiddleware('DeleteUser-MW', log),
          ]).name('deleteUser');
        },
      )
          .name('admin');

      final engine = Engine();
      engine.use(
        '/api/v3',
        router3,
        middlewares: [makeMiddleware('EngineMW-forRouter3', log)],
      );

      // Build
      engine.build();

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
      final mwLabels = r.middlewares.map((mw) => _middlewareLabel(mw, log)).toList();
      expect(
        mwLabels,
        equals(['EngineMW-forRouter3', 'Router3-GMW', 'AdminGroup-MW', 'DeleteUser-MW']),
      );
    });
  });
}

/// Utility: If we want to figure out which label was used to create this middleware,
/// we can look it up in a static map or hold a closure reference. For simplicity,
/// we'll just define a small function that returns the label we used in `makeMiddleware`.
///
/// But since the test doesn't actually *run* the middlewares, we can't just read from `log`.
/// Instead, we do an identity check. We'll store references in a global or use the label approach.
///
/// If you just want to confirm the *count* or presence, you can skip this step.
///
/// For a straightforward approach, let's store an identity map:
final _middlewareIdentityMap = <Middleware, String>{};

Middleware makeMiddleware(String label, List<String> log) {
  // We'll wrap the real function in a closure so we can store it in a map
  final mw = (dynamic req, dynamic res, void Function() next) {
    // For demonstration, you might log or do something
    log.add(label);
    next();
  };
  _middlewareIdentityMap[mw] = label;
  return mw;
}

/// Helper to get the label for a given middleware reference,
/// or "Unknown" if not found in the map.
String _middlewareLabel(Middleware mw, List<String> log) {
  return _middlewareIdentityMap[mw] ?? "UnknownMiddleware";
}
