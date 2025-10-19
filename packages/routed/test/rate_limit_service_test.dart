import 'dart:async';

import 'package:routed/src/cache/cache_manager.dart';
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/events/event_manager.dart';
import 'package:routed/src/events/rate_limit/rate_limit_events.dart';
import 'package:routed/src/rate_limit/backend.dart';
import 'package:routed/src/rate_limit/policy.dart';
import 'package:routed/src/rate_limit/service.dart';
import 'package:routed/src/request.dart';
import 'package:server_testing/mock.dart';
import 'package:test/test.dart';

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

    final mockRequest = setupRequest(
      'GET',
      '/resource',
      requestHeaders: {
        'x-user-id': ['user-123'],
      },
    );

    final request = Request(mockRequest, const {}, EngineConfig());

    final first = await service.check(request);
    expect(first, isNull); // allowed

    final second = await service.check(request);
    expect(second, isNotNull);
    expect(second!.allowed, isFalse);

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
