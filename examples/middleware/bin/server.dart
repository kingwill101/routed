import 'package:routed/routed.dart';

// Logging middleware
Future<void> loggingMiddleware(EngineContext ctx) async {
  final startTime = DateTime.now();
  print('[${ctx.request.method}] ${ctx.request.path} - Started');

  await ctx.next();

  final duration = DateTime.now().difference(startTime);
  print(
      '[${ctx.request.method}] ${ctx.request.path} - ${ctx.response.statusCode} (${duration.inMilliseconds}ms)');
}

// Authentication middleware
Future<void> authMiddleware(EngineContext ctx) async {
  final token = ctx.requestHeader('Authorization');
  if (token != 'secret-token') {
    return ctx.json({'error': 'Unauthorized'}, statusCode: 401);
  }
  await ctx.next();
}

// Rate limiting middleware
Future<void> rateLimitMiddleware(EngineContext ctx) async {
  final requests = <String, List<DateTime>>{};
  final ip = ctx.request.ip;
  final now = DateTime.now();

  // Clean old requests
  requests[ip] = requests[ip]
          ?.where((time) => now.difference(time).inMinutes < 1)
          .toList() ??
      [];

  // Check rate limit (max 10 requests per minute)
  if ((requests[ip]?.length ?? 0) >= 10) {
    return ctx.json({'error': 'Too many requests', 'retry_after': '60 seconds'},
        statusCode: 429);
  }

  // Add request
  requests[ip] = [...(requests[ip] ?? []), now];

  await ctx.next();
}

void main() async {
  final engine = Engine(middlewares: [loggingMiddleware]);

  // Public routes
  engine.get('/public', (ctx) {
    return ctx.json({'message': 'Public route'});
  });

  // Routes with rate limiting
  engine.group(
    path: '/api',
    middlewares: [rateLimitMiddleware],
    builder: (router) {
      router.get('/status', (ctx) {
        return ctx.json({'status': 'OK'});
      });
    },
  );

  // Protected routes
  engine.group(
    path: '/admin',
    middlewares: [authMiddleware],
    builder: (router) {
      router.get('/dashboard', (ctx) {
        return ctx
            .json({'message': 'Admin dashboard', 'user': 'Authenticated user'});
      });

      router.post('/update', (ctx) async {
        final body = await ctx.request.body();
        return ctx.json({'message': 'Update successful', 'data': body});
      });
    },
  );

  // Error handling route
  engine.get('/error', (ctx) {
    throw Exception('Intentional error');
  });

  // Start the server
  await engine.serve(port: 3000);
  print('Server running at http://localhost:3000');
}
