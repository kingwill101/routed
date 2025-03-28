import 'package:routed/routed.dart';

void main() async {
  final engine = Engine();

  // Basic route matching
  engine.get('/hello', (ctx) {
    return ctx.json({'message': 'Basic route match'});
  });

  // Route with required parameter
  engine.get('/users/{id}', (ctx) {
    final id = ctx.param('id');
    return ctx.json({'message': 'User route with parameter', 'id': id});
  });

  // Route with optional parameter
  engine.get('/posts/{page?}', (ctx) {
    final page = ctx.param('page') ?? '1';
    return ctx.json({'message': 'Posts with optional page', 'page': page});
  });

  // Route with type constraints
  engine.get('/items/{id:int}', (ctx) {
    final id = ctx.param('id');
    return ctx
        .json({'message': 'Item route with integer constraint', 'id': id});
  });

  // Route with multiple parameters
  engine.get('/users/{userId}/posts/{postId}', (ctx) {
    return ctx.json({
      'message': 'Nested route with multiple parameters',
      'userId': ctx.param('userId'),
      'postId': ctx.param('postId')
    });
  });

  // Route with regex constraint
  engine.get('/products/{code}', (ctx) {
    return ctx.json({
      'message': 'Product route with regex constraint',
      'code': ctx.param('code')
    });
  }, constraints: {
    'code': r'^[A-Z]{2}\d{3}$' // Matches format: XX000
  });

  // Route with domain constraint
  engine.get('/admin', (ctx) {
    return ctx.json({
      'message': 'Admin route with domain constraint',
      'host': ctx.request.host
    });
  }, constraints: {'domain': r'^admin\.localhost$'});

  // Wildcard route
  engine.get('/files/{*path}', (ctx) {
    final path = ctx.param('path');
    return ctx.json({'message': 'Wildcard route match', 'path': path});
  });

  // Route group with prefix
  engine.group(
      path: '/api/v1',
      builder: (router) {
        // Matches /api/v1/status
        router.get('/status', (ctx) {
          return ctx
              .json({'message': 'API status route in group', 'version': 'v1'});
        });

        // Nested group
        router.group(
            path: '/admin',
            builder: (admin) {
              // Matches /api/v1/admin/dashboard
              admin.get('/dashboard', (ctx) {
                return ctx.json({'message': 'Admin dashboard in nested group'});
              });
            });
      });

  // Fallback route for unmatched requests
  engine.fallback((ctx) {
    return ctx.json({'error': 'Route not found', 'path': ctx.request.path},
        statusCode: 404);
  });

  // Start the server
  await engine.serve(port: 3000, echo: true);
}
