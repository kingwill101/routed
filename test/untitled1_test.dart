// test/my_router_test.dart
import 'package:test/test.dart';
import 'package:untitled1/untitled1.dart';

void main() {
  group('Router Tests', () {
    test('Basic group/route registration and naming', () {
      final router = Router();

      router.group(
        path: '/api',
        builder: (apiGroup) {
          apiGroup.group(
            path: '/books',
            builder: (booksGroup) {
              booksGroup.get('/', (req, res) {}).name('list');
            },
          ).name('books');

          apiGroup.get('/health', (req, res) {}).name('health.check');

          apiGroup.group(
            path: '/users',
            builder: (usersGroup) {
              usersGroup.get('/', (req, res) {}).name('list');
            },
          ).name('users');
        },
      ).name("api");

      router.build();

      final allRoutes = router.getAllRoutes();
      expect(allRoutes.length, 3);

      // Sort for consistent checking
      allRoutes.sort((a, b) => a.path.compareTo(b.path));

      // 1: /api/books/
      expect(allRoutes[0].method, 'GET');
      expect(allRoutes[0].path, '/api/books/');
      expect(allRoutes[0].name, 'api.books.list');

      // 2: /api/health
      expect(allRoutes[1].method, 'GET');
      expect(allRoutes[1].path, '/api/health');
      expect(allRoutes[1].name, 'api.health.check');

      // 3: /api/users/
      expect(allRoutes[2].method, 'GET');
      expect(allRoutes[2].path, '/api/users/');
      expect(allRoutes[2].name, 'api.users.list');
    });
  });
}
