import 'package:routed/routed.dart';

void main() async {
  final engine = Engine();

  // Direct route registration
  engine.get(
    '/users',
    (ctx) => ctx.json({
      'message': 'List users',
      'users': ['John', 'Jane', 'Bob'],
    }),
  );

  engine.post('/users', (ctx) async {
    final body = await ctx.body();
    return ctx.json({'message': 'User created', 'data': body});
  });

  // Route with parameters
  engine
      .get('/users/{id}', (ctx) {
        final id = ctx.param('id');
        return ctx.json({'user_id': id, 'name': 'User $id'});
      })
      .name('users.show');

  // Route group with middleware
  engine.group(
    path: '/admin',
    middlewares: [
      (ctx, next) async {
        final token = ctx.requestHeader('Authorization');
        if (token != 'secret') {
          return ctx.json({'error': 'Unauthorized'}, statusCode: 401);
        }
        return next();
      },
    ],
    builder: (router) {
      router.get(
        '/stats',
        (ctx) => ctx.json({
          'stats': {'users': 100, 'posts': 500},
        }),
      );
    },
  );

  // Named routes with parameters
  engine
      .get('/articles/{slug}', (ctx) {
        final slug = ctx.param('slug');
        return ctx.json({
          'article': {'slug': slug, 'title': 'Article about $slug'},
          'url': ctx.route('articles.show', {'slug': slug}),
        });
      })
      .name('articles.show');

  // Start the server
  await engine.serve(port: 3000);
  print('Server running at http://localhost:3000');
}
