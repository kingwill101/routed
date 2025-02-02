// test/my_router_test.dart
import 'package:routed/src/router/router.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

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

    test('Group-level middlewares + route-level middlewares merge properly',
        () {
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
              sub.get('/route', (c) {
                // ...
              }, middlewares: [makeMiddleware('RouteMW', log)]).name(
                  'subroute');
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
      final names =
          route.finalMiddlewares.map((mw) => middlewareLabel(mw, log)).toList();
      expect(names, equals(['GroupMW1', 'GroupMW2', 'RouteMW']));
    });
  });
}
