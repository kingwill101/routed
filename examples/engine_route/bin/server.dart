import 'package:routed/routed.dart';

void main() async {
  final engine = Engine();

  // Basic route
  engine.get('/hello', (ctx) => ctx.string('Hello, World!'));

  // Route with parameter and name
  engine.get('/users/{id}', (ctx) {
    final id = ctx.param('id');
    return ctx.json({
      'id': id,
      'url': route('users.show', {'id': id}),
    });
  }).name('users.show');

  // Route with typed parameter
  engine.get('/items/{id:int}', (ctx) {
    final id = ctx.param('id');
    return ctx.json({
      'id': id,
      'type': 'integer',
    });
  });

  // Route with optional parameter
  engine.get('/posts/{page?}', (ctx) {
    final page = ctx.param('page') ?? '1';
    return ctx.json({
      'page': page,
      'isDefault': page == '1',
    });
  });

  // Route with wildcard parameter
  engine.get('/files/{*path}', (ctx) {
    final path = ctx.param('path');
    return ctx.json({
      'path': path,
      'segments': path?.split('/'),
    });
  });

  // Route with regex constraint
  engine.get('/products/{id}', (ctx) {
    final id = ctx.param('id');
    return ctx.json({
      'id': id,
      'type': 'product',
    });
  }, constraints: {
    'id': r'\d{3}' // Must be exactly 3 digits
  });

  // Route with domain constraint
  engine.get('/admin', (ctx) {
    return ctx.json({
      'section': 'admin',
      'host': ctx.request.host,
    });
  }, constraints: {'domain': r'admin\.localhost'});

  // Fallback route
  engine.fallback((ctx) {
    return ctx.json({
      'error': 'Route not found',
      'path': ctx.request.path,
    }, statusCode: 404);
  });

  // Start the server
  await engine.serve(port: 3000);
  print('Server running at http://localhost:3000');
}
