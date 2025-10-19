import 'package:routed/routed.dart';

void main() async {
  final engine = Engine();

  // Regular route
  engine.get('/hello', (ctx) => ctx.string('Hello, World!'));

  // Nested API groups with fallbacks
  engine.group(
    path: '/api',
    builder: (api) {
      // General API fallback
      api.fallback((ctx) => ctx.json({
            'error': 'API route not found',
            'scope': 'api',
            'path': ctx.uri.path,
          }));

      api.group(
        path: '/v1',
        builder: (v1) {
          // Regular API route
          v1.get('/users', (ctx) => ctx.json({'users': []}));

          // V1-specific fallback
          v1.fallback((ctx) => ctx.json({
                'error': 'V1 API route not found',
                'scope': 'v1',
                'path': ctx.uri.path,
              }));
        },
      );
    },
  );

  // Group with middleware and fallback
  int middlewareCalled = 0;
  engine.group(
    path: '/secured',
    middlewares: [
      (ctx, next) async {
        middlewareCalled++;
        print('Middleware called: $middlewareCalled times');
        return ctx.response;
      },
    ],
    builder: (router) {
      router.fallback((ctx) => ctx.json({
            'error': 'Secured route not found',
            'path': ctx.uri.path,
          }));
    },
  );

  // Global fallback for any unmatched route
  engine.fallback((ctx) {
    return ctx.string('Fallback: ${ctx.uri.path}');
  });

  // Start the server
  await engine.serve(port: 3000);
  print('Server running at http://localhost:3000');
}
