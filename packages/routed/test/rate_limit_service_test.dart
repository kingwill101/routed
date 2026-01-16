import 'dart:async';

import 'package:routed/routed.dart';
import 'package:routed/src/rate_limit/backend.dart';
import 'package:routed/src/rate_limit/policy.dart';
import 'package:routed/src/rate_limit/service.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'test_engine.dart';

void main() {
  group('RequestMatcher', () {
    test('matches by method and path pattern', () {
      final matcher = RequestMatcher(method: 'GET', pattern: '/api/v1/*');

      final matching = Request(
        setupRequest('GET', '/api/v1/users'),
        {},
        EngineConfig(),
      );
      final wrongMethod = Request(
        setupRequest('POST', '/api/v1/users'),
        {},
        EngineConfig(),
      );
      final wrongPath = Request(
        setupRequest('GET', '/health'),
        {},
        EngineConfig(),
      );

      expect(matcher.matches(matching), isTrue);
      expect(matcher.matches(wrongMethod), isFalse);
      expect(matcher.matches(wrongPath), isFalse);
    });
  });

  group('RateLimitService policy matching', () {
    test('ignores policies that do not match the request', () async {
      final cacheManager = CacheManager();
      cacheManager.registerStore('rate', {'driver': 'array'});
      final backend = CacheRateLimiterBackend(
        repository: cacheManager.store('rate'),
      );

      final policy = CompiledRateLimitPolicy(
        name: 'api',
        matcher: RequestMatcher(method: 'GET', pattern: '/api/v1/*'),
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
      final emitted = <RateLimitEvent>[];
      final sub = events.on<RateLimitEvent>().listen(emitted.add);

      final request = Request(
        setupRequest(
          'GET',
          '/health',
          requestHeaders: {'x-user-id': ['user-1']},
        ),
        {},
        EngineConfig(),
      );

      final outcome = await service.check(request);
      expect(outcome, isNull);
      expect(emitted, isEmpty);

      await sub.cancel();
      await service.dispose();
      await backend.close();
    });

    test('ignores policies when identity cannot be resolved', () async {
      final cacheManager = CacheManager();
      cacheManager.registerStore('rate', {'driver': 'array'});
      final backend = CacheRateLimiterBackend(
        repository: cacheManager.store('rate'),
      );

      final policy = CompiledRateLimitPolicy(
        name: 'api',
        matcher: RequestMatcher(method: 'GET', pattern: '/api/v1/*'),
        keyResolver: const HeaderKeyResolver('x-user-id'),
        algorithm: buildBucketConfig(
          capacity: 1,
          refillInterval: const Duration(minutes: 1),
        ),
        backend: backend,
        failover: RateLimitFailoverMode.allow,
      );

      final service = RateLimitService([policy]);

      final request = Request(
        setupRequest('GET', '/api/v1/users'),
        {},
        EngineConfig(),
      );

      final outcome = await service.check(request);
      expect(outcome, isNull);

      await service.dispose();
      await backend.close();
    });

    test('evaluates matching policies in order and can block later', () async {
      final backend = StubRateLimiterBackend({
        'first:user-1': RateLimitOutcome.allowed(remaining: 1),
        'second:user-1': RateLimitOutcome.blocked(
          retryAfter: const Duration(seconds: 5),
          remaining: 0,
        ),
      });

      final policies = [
        CompiledRateLimitPolicy(
          name: 'first',
          matcher: RequestMatcher(method: 'GET', pattern: '/api/v1/*'),
          keyResolver: const HeaderKeyResolver('x-user-id'),
          algorithm: buildBucketConfig(
            capacity: 1,
            refillInterval: const Duration(minutes: 1),
          ),
          backend: backend,
          failover: RateLimitFailoverMode.allow,
        ),
        CompiledRateLimitPolicy(
          name: 'second',
          matcher: RequestMatcher(method: 'GET', pattern: '/api/v1/*'),
          keyResolver: const HeaderKeyResolver('x-user-id'),
          algorithm: buildBucketConfig(
            capacity: 1,
            refillInterval: const Duration(minutes: 1),
          ),
          backend: backend,
          failover: RateLimitFailoverMode.allow,
        ),
      ];

      final service = RateLimitService(policies);
      final request = Request(
        setupRequest(
          'GET',
          '/api/v1/users',
          requestHeaders: {'x-user-id': ['user-1']},
        ),
        {},
        EngineConfig(),
      );

      final outcome = await service.check(request);
      expect(outcome, isNotNull);
      expect(outcome!.allowed, isFalse);
      expect(backend.seen, equals(['first:user-1', 'second:user-1']));

      await service.dispose();
      await backend.close();
    });

    test('stops evaluating after the first blocked policy', () async {
      final backend = StubRateLimiterBackend({
        'first:user-1': RateLimitOutcome.blocked(
          retryAfter: const Duration(seconds: 5),
          remaining: 0,
        ),
        'second:user-1': RateLimitOutcome.allowed(remaining: 1),
      });

      final policies = [
        CompiledRateLimitPolicy(
          name: 'first',
          matcher: RequestMatcher(method: 'GET', pattern: '/api/v1/*'),
          keyResolver: const HeaderKeyResolver('x-user-id'),
          algorithm: buildBucketConfig(
            capacity: 1,
            refillInterval: const Duration(minutes: 1),
          ),
          backend: backend,
          failover: RateLimitFailoverMode.allow,
        ),
        CompiledRateLimitPolicy(
          name: 'second',
          matcher: RequestMatcher(method: 'GET', pattern: '/api/v1/*'),
          keyResolver: const HeaderKeyResolver('x-user-id'),
          algorithm: buildBucketConfig(
            capacity: 1,
            refillInterval: const Duration(minutes: 1),
          ),
          backend: backend,
          failover: RateLimitFailoverMode.allow,
        ),
      ];

      final service = RateLimitService(policies);
      final request = Request(
        setupRequest(
          'GET',
          '/api/v1/users',
          requestHeaders: {'x-user-id': ['user-1']},
        ),
        {},
        EngineConfig(),
      );

      final outcome = await service.check(request);
      expect(outcome, isNotNull);
      expect(outcome!.allowed, isFalse);
      expect(backend.seen, equals(['first:user-1']));

      await service.dispose();
      await backend.close();
    });
  });

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

class StubRateLimiterBackend implements RateLimiterBackend {
  StubRateLimiterBackend(this.responses);

  final Map<String, RateLimitOutcome> responses;
  final List<String> seen = [];

  @override
  Future<RateLimitOutcome> consume(
    String bucketKey,
    RateLimitAlgorithmConfig config,
    DateTime now, {
    RateLimitFailoverMode failover = RateLimitFailoverMode.allow,
  }) async {
    seen.add(bucketKey);
    return responses[bucketKey] ?? RateLimitOutcome.allowed(remaining: 1);
  }

  @override
  Future<void> close() async {}
}
