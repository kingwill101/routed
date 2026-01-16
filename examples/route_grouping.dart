import 'package:routed/routed.dart';

void main() async {
  final engine = Engine();

  final adminAuth = (EngineContext ctx, Next next) async {
    final token = ctx.requestHeader('Authorization');
    if (token != 'admin-token') {
      return ctx.json({'error': 'Unauthorized access'}, statusCode: 401);
    }
    return await next();
  };

  // Basic route group
  engine.group(
    path: '/admin',
    middlewares: [
      // Auth middleware
      adminAuth,
    ],
    builder: (router) {
      router.get('/dashboard', (ctx) {
        return ctx.json({'section': 'dashboard', 'user': 'admin'});
      });

      router.get('/users', (ctx) {
        return ctx.json({'section': 'users', 'count': 100});
      });

      router
          .get('/health', (ctx) => ctx.json({'status': 'ok'}))
          .withoutMiddleware([adminAuth]);
    },
  );

  // API versioning with nested groups
  engine.group(
    path: '/api',
    middlewares: [
      // API middleware
      (EngineContext ctx, Next next) async {
        ctx.setHeader('X-API-Version', ctx.param('version') ?? 'unknown');
        return await next();
      },
    ],
    builder: (api) {
      // V1 API group
      api.group(
        path: '/v1',
        builder: (v1) {
          v1.get('/status', (ctx) {
            return ctx.json({'version': 'v1', 'status': 'active'});
          });
        },
      );

      // V2 API group
      api.group(
        path: '/v2',
        builder: (v2) {
          v2.get('/status', (ctx) {
            return ctx.json({
              'version': 'v2',
              'status': 'beta',
              'features': ['new_api', 'improved_performance'],
            });
          });
        },
      );
    },
  );

  // Resource group with CRUD operations
  engine.group(
    path: '/posts',
    builder: (posts) {
      // List posts
      posts.get('/', (ctx) {
        return ctx.json({
          'posts': [
            {'id': 1, 'title': 'First post'},
            {'id': 2, 'title': 'Second post'},
          ],
        });
      });

      // Get single post
      posts.get('/{id:int}', (ctx) {
        return ctx.json({'id': ctx.param('id'), 'title': 'Post details'});
      });

      // Post comments group
      posts.group(
        path: '/{post_id:int}/comments',
        builder: (comments) {
          comments.get('/', (ctx) {
            return ctx.json({
              'post_id': ctx.param('post_id'),
              'comments': [
                {'id': 1, 'text': 'Great post!'},
                {'id': 2, 'text': 'Thanks for sharing'},
              ],
            });
          });
        },
      );
    },
  );

  // Start the server
  await engine.serve(port: 3000);
  print('Server running at http://localhost:3000');
  print('\nAvailable routes:');
  print('Admin routes (requires Authorization: admin-token header):');
  print('  GET /admin/dashboard');
  print('  GET /admin/users');
  print('  GET /admin/health (no auth required)');
  print('\nAPI routes:');
  print('  GET /api/v1/status');
  print('  GET /api/v2/status');
  print('\nResource routes:');
  print('  GET /posts');
  print('  GET /posts/{id}');
  print('  GET /posts/{post_id}/comments');
}
