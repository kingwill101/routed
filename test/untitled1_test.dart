// test/my_router_test.dart
import 'package:test/test.dart';
import 'package:untitled1/untitled1.dart';

void main() {
  group('MyRouter Tests', () {
    test('Produces correct paths and names', () {
      final router = Router();

      router.group(
        path: '/api',
        builder: (apiGroup) {
          apiGroup.group(
            path: '/books/',
            builder: (booksGroup) {
              booksGroup.get('/', (req, res) {}).name('list');
            },
          ).name('books');

          apiGroup.get('/health', (req, res) {}).name('health.check');

          apiGroup.group(
            path: '/users/',
            builder: (usersGroup) {
              usersGroup.get('/', (req, res) {}).name('list');
            },
          ).name('users');
        },
      ).name('api');

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
}
