import 'package:untitled1/untitled1.dart';

void main() {
  final router = Router(groupName: 'v1', path: '/api');
  // The top-level router itself is named "v1" with base path "/api"

  // e.g. GET /api/books => "v1.books.index"
  router.group(
    path: '/books',
    builder: (booksGroup) {
      booksGroup.get('/', (req, res) {
        res.write('Listing books');
      }).name('index');

      booksGroup.post('/', (req, res) {
        res.write('Creating book');
      }).name('create');
    },
  ).name('books'); // => final route names "v1.books.index", "v1.books.create"

  // e.g. POST /api/auth/login => "v1.auth.login"
  router.group(
    path: '/auth',
    builder: (authGroup) {
      authGroup.post('/login', (req, res) {
        res.write('Logging in...');
      }).name('login');

      authGroup.post('/logout', (req, res) {
        res.write('Logging out...');
      }).name('logout');
    },
  ).name('auth');

  // finalize the names
  router.build();

  // print them
  router.printRoutes();
}
