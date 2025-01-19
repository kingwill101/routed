// example/engine_example.dart


import 'package:untitled1/untitled1.dart';

void main() {
  // Create two separate routers, r1 and r2:
  final r1 = Router(groupName: 'v1');
  r1.group(path: '/books', builder: (booksGroup) {
    booksGroup.get('/', (req, res) {
      // ...
    }).name('list');

    booksGroup.post('/', (req, res) {
      // ...
    }).name('create');
  }).name('books'); // => final route name "v1.books.list", "v1.books.create"

  final r2 = Router(groupName: 'v2');
  r2.group(path: '/products', builder: (productsGroup) {
    productsGroup.get('/', (req, res) {
      // ...
    }).name('index');
  }).name('products'); // => final route name "v2.products.index"

  // Simple example middlewares
  authMiddleware(req, res, next) {
    print('Auth check...');
    next();
  }
  loggerMiddleware(req, res, next) {
    print('Logging...');
    next();
  }

  // Create an engine and mount r1 and r2 at different prefixes
  final engine = Engine();

  // Mount r1 under "/api/v1" with one middleware
  engine.use(
    '/api/v1',
    r1,
    middlewares: [authMiddleware],
  );

  // Mount r2 under "/api/v2" with two middlewares
  engine.use(
    '/api/v2',
    r2,
    middlewares: [authMiddleware, loggerMiddleware],
  );

  // Build the engine route table
  engine.build();

  // Print them:
  engine.printRoutes();
}
