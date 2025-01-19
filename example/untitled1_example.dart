// example/main_example.dart

import 'package:untitled1/untitled1.dart';

void main() {
  // --------------------
  //  DEFINE ROUTER #1
  // --------------------
  final router1 = Router(groupName: 'v1', path: '/r1', middlewares: [
        (req, res, next) {
      print('router1-level MW #1');
      next();
    },
  ]);

  // a group => /r1/books => name => v1.books
  router1
      .group(
    path: '/books',
    middlewares: [
          (req, res, next) {
        print('group-level MW for /books');
        next();
      }
    ],
    builder: (booksGroup) {
      booksGroup.get('/', (req, res) {
        res.write('List books from router1');
      }, middlewares: [
            (req, res, next) {
          print('route-level MW for GET /books');
          next();
        }
      ]).name('list');
    },
  )
      .name('books');

  // Another route => /r1/health => name => v1.health
  router1.get('/health', (req, res) {
    res.write('Health check router1');
  }, middlewares: [
        (req, res, next) {
      print('route-level MW for GET /health');
      next();
    }
  ]).name('health');

  // --------------------
  //  DEFINE ROUTER #2
  // --------------------
  final router2 = Router(groupName: 'v2', path: '/r2');

  // /r2/items => v2.items
  router2
      .group(
    path: '/items',
    builder: (itemsGroup) {
      itemsGroup.post('/', (req, res) {
        res.write('Create item in router2');
      }).name('create');
    },
  )
      .name('items');

  // --------------------
  //  ENGINE
  // --------------------
  final engine = Engine();

  // MOUNT router1 at /api/v1 plus engine-level middleware
  engine.use('/api/v1', router1, middlewares: [
        (req, res, next) {
      print('ENGINE MW #1 for router1');
      next();
    }
  ]);

  // MOUNT router2 at /api/v2 plus engine-level middleware
  engine.use('/api/v2', router2, middlewares: [
        (req, res, next) {
      print('ENGINE MW #1 for router2');
      next();
    },
        (req, res, next) {
      print('ENGINE MW #2 for router2');
      next();
    }
  ]);

  // BUILD
  engine.build();

  // PRINT FINAL ROUTES
  engine.printRoutes();
}
