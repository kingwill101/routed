// example/my_router_example.dart
import 'package:untitled1/untitled1.dart';

void main() {
  final router = Router();

  router
      .group(
        path: '/api',
        builder: (apiGroup) {
          apiGroup
              .group(
                path: '/books',
                builder: (booksGroup) {
                  booksGroup.get('/', (req, res) {
                    res.write('List books');
                  }).name('list');
                },
              )
              .name('books');

          apiGroup.get('/health', (req, res) {
            res.write('System health check');
          }).name('health.check');

          apiGroup
              .group(
                path: '/users',
                builder: (usersGroup) {
                  usersGroup.get('/', (req, res) {
                    res.write('List Users');
                  }).name('list');
                },
              )
              .name('users');
        },
      )
      .name("api");

  router.build();
  router.printRoutes();
}
