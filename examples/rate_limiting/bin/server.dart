// Rate Limiting Example
//
// Demonstrates typed rate limiting with multiple strategies (token bucket,
// sliding window, quota) and key resolvers.
//
// Run the server:
//   dart run bin/server.dart
//
// Then run the client to exercise each policy:
//   dart run bin/client.dart
//
// You can also test manually with curl:
//   for i in $(seq 1 12); do curl -s -w "\n%{http_code}\n" http://localhost:3000/health; done
import 'dart:io';

import 'package:routed/routed.dart';

Future<void> main() async {
  final backend = CacheRateLimiterBackend(
    repository: RepositoryImpl(ArrayStore(), 'rate-limit', ''),
  );
  final service = RateLimitService(
    compileRateLimitPolicies(
      specs: [
        const RateLimitPolicySpec(
          name: 'global',
          match: '**',
          method: null,
          strategy: RateLimitStrategy.tokenBucket,
          capacity: 10,
          interval: Duration(seconds: 30),
          window: Duration.zero,
          period: Duration.zero,
          burstMultiplier: 1.5,
          key: RateLimitKeySpec.ip(),
        ),
        const RateLimitPolicySpec(
          name: 'auth',
          match: '/auth/**',
          method: null,
          strategy: RateLimitStrategy.slidingWindow,
          capacity: 5,
          interval: Duration.zero,
          window: Duration(minutes: 1),
          period: Duration.zero,
          burstMultiplier: null,
          key: RateLimitKeySpec.ip(),
        ),
        const RateLimitPolicySpec(
          name: 'api_key',
          match: '/api/**',
          method: null,
          strategy: RateLimitStrategy.slidingWindow,
          capacity: 3,
          interval: Duration.zero,
          window: Duration(minutes: 1),
          period: Duration.zero,
          burstMultiplier: null,
          key: RateLimitKeySpec.header('X-API-Key'),
        ),
        const RateLimitPolicySpec(
          name: 'daily_quota',
          match: '/quota',
          method: null,
          strategy: RateLimitStrategy.quota,
          capacity: 100,
          interval: Duration.zero,
          window: Duration.zero,
          period: Duration(days: 1),
          burstMultiplier: null,
          key: RateLimitKeySpec.ip(),
        ),
      ],
      backend: backend,
      defaultFailover: RateLimitFailoverMode.allow,
    ),
  );
  final providers =
      Engine.builtins
          .where((provider) => provider is! RoutedRateLimitProvider)
          .toList()
        ..add(RoutedRateLimitProvider(RateLimitConfig(service: service)));
  final engine = await Engine.create(providers: providers);
  engine.addGlobalMiddleware(rateLimitMiddleware(service));

  // -----------------------------------------------------------------------
  // Routes — each demonstrates a different typed policy.
  // -----------------------------------------------------------------------

  // Matches the "global" policy (token bucket, 10 req / 30s)
  engine.get('/health', (ctx) {
    return ctx.json({'status': 'ok', 'time': DateTime.now().toIso8601String()});
  });

  // Matches the "auth" policy (sliding window, 5 req / 1m)
  engine.group(
    path: '/auth',
    builder: (router) {
      router.post('/login', (ctx) async {
        return ctx.json({'message': 'Login successful', 'token': 'abc123'});
      });

      router.post('/register', (ctx) async {
        return ctx.json({'message': 'User registered'});
      });
    },
  );

  // Matches the "api_key" policy (sliding window, 3 req / 1m, keyed by header)
  engine.group(
    path: '/api',
    builder: (router) {
      router.get('/data', (ctx) {
        final apiKey = ctx.headers.value('X-API-Key');
        return ctx.json({
          'data': [1, 2, 3],
          'api_key': apiKey ?? 'none',
        });
      });
    },
  );

  // Matches the "daily_quota" policy (quota, 100 req / 1d)
  engine.get('/quota', (ctx) {
    return ctx.json({
      'message': 'Quota endpoint',
      'time': DateTime.now().toIso8601String(),
    });
  });

  // -----------------------------------------------------------------------
  // Start the server
  // -----------------------------------------------------------------------

  await engine.serve(port: 3000, echo: true);
  print('Rate limiting example running at http://localhost:3000');
  print('');
  print('Endpoints:');
  print('  GET  /health         — global policy (10 req / 30s, token bucket)');
  print('  POST /auth/login     — auth policy   (5 req / 1m, sliding window)');
  print('  POST /auth/register  — auth policy   (5 req / 1m, sliding window)');
  print(
    '  GET  /api/data       — api_key policy (3 req / 1m, keyed by X-API-Key)',
  );
  print('  GET  /quota          — daily quota    (100 req / 1d)');
  print('');
  print('Run "dart run bin/client.dart" to see rate limiting in action');

  ProcessSignal.sigint.watch().listen((_) async {
    await engine.close();
    exit(0);
  });
}
