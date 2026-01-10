import 'dart:async';

import 'package:routed/routed.dart';
import 'package:routed/src/rate_limit/backend.dart';
import 'package:routed/src/rate_limit/policy.dart';
import 'package:routed/src/rate_limit/service.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'test_engine.dart';

void main() {
  test('emits events for allowed and blocked outcomes', () async {
    final cacheManager = CacheManager();
    cacheManager.registerStore('rate', {'driver': 'array'});
    final backend = CacheRateLimiterBackend(
      repository: cacheManager.store('rate'),
    );

    final policy = CompiledRateLimitPolicy(
      name: 'header-policy',
      matcher: RequestMatcher(method: 'GET', pattern: '*'),
      keyResolver: const HeaderKeyResolver('x-user-id'),
      algorithm: buildBucketConfig(
        capacity: 1,
        refillInterval: const Duration(minutes: 1),
      ),
      backend: backend,
      failover: RateLimitFailoverMode.allow,
    );

    final events = EventManager();
    final service = RateLimitService([policy], events: events);

    final subscriptions = <RateLimitEvent>[];
    final sub = events.on<RateLimitEvent>().listen(subscriptions.add);

    final engine = testEngine();
    engine.get('/resource', (ctx) async {
      final result = await service.check(ctx.request);
      if (result == null || result.allowed) {
        return ctx.string('ok');
      }
      return ctx.json({
        'error': 'rate_limited',
      }, statusCode: HttpStatus.tooManyRequests);
    });

    await engine.initialize();
    final client = TestClient(
      RoutedRequestHandler(engine),
      mode: TransportMode.ephemeralServer,
    );
    addTearDown(() async {
      await client.close();
      await engine.close();
    });

    final first = await client.get(
      '/resource',
      headers: {
        'x-user-id': ['user-123'],
      },
    );
    first.assertStatus(HttpStatus.ok);

    final second = await client.get(
      '/resource',
      headers: {
        'x-user-id': ['user-123'],
      },
    );
    second.assertStatus(HttpStatus.tooManyRequests);

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(subscriptions.length, 2);
    expect(subscriptions.first, isA<RateLimitAllowedEvent>());
    final allowedEvent = subscriptions.first as RateLimitAllowedEvent;
    expect(allowedEvent.policy, 'header-policy');
    expect(allowedEvent.identity, 'user-123');
    expect(allowedEvent.remaining, isZero);

    expect(subscriptions.last, isA<RateLimitBlockedEvent>());
    final blockedEvent = subscriptions.last as RateLimitBlockedEvent;
    expect(blockedEvent.policy, 'header-policy');
    expect(blockedEvent.identity, 'user-123');
    expect(blockedEvent.retryAfter, greaterThan(Duration.zero));

    await sub.cancel();
    await service.dispose();
    await backend.close();
  });
}
