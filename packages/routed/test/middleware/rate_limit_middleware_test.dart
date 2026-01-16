import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed/src/middleware/rate_limit.dart';
import 'package:routed/src/rate_limit/backend.dart';
import 'package:routed/src/rate_limit/policy.dart';
import 'package:routed/src/rate_limit/service.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import '../test_engine.dart';

void main() {
  TestClient? client;

  tearDown(() async {
    await client?.close();
  });

  test('rateLimitMiddleware blocks matching routes and skips non-matching ones',
      () async {
    final cacheManager = CacheManager();
    cacheManager.registerStore('rate', {'driver': 'array'});
    final backend = CacheRateLimiterBackend(
      repository: cacheManager.store('rate'),
    );

    final policy = CompiledRateLimitPolicy(
      name: 'api',
      matcher: RequestMatcher(method: 'GET', pattern: '/api/*'),
      keyResolver: const HeaderKeyResolver('x-user-id'),
      algorithm: buildBucketConfig(
        capacity: 1,
        refillInterval: const Duration(minutes: 1),
      ),
      backend: backend,
      failover: RateLimitFailoverMode.allow,
    );

    final service = RateLimitService([policy]);
    final engine = testEngine(middlewares: [rateLimitMiddleware(service)])
      ..get('/api/test', (ctx) => ctx.string('ok'))
      ..get('/health', (ctx) => ctx.string('ok'));

    await engine.initialize();
    client = TestClient(
      RoutedRequestHandler(engine),
      mode: TransportMode.ephemeralServer,
    );

    addTearDown(() async {
      await engine.close();
      await service.dispose();
      await backend.close();
    });

    final first = await client!.get(
      '/api/test',
      headers: {'x-user-id': ['user-1']},
    );
    first.assertStatus(HttpStatus.ok);

    final second = await client!.get(
      '/api/test',
      headers: {'x-user-id': ['user-1']},
    );
    second
      ..assertStatus(HttpStatus.tooManyRequests)
      ..assertHasHeader('Retry-After');

    final passthrough = await client!.get(
      '/health',
      headers: {'x-user-id': ['user-1']},
    );
    passthrough.assertStatus(HttpStatus.ok);
  });
}
