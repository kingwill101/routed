import 'package:routed/src/cache/cache_manager.dart';
import 'dart:async';

import 'package:routed/src/contracts/cache/repository.dart';
import 'package:routed/src/contracts/cache/store.dart';
import 'package:routed/src/rate_limit/backend.dart';
import 'package:routed/src/rate_limit/policy.dart';
import 'package:test/test.dart';

void main() {
  group('CacheRateLimiterBackend', () {
    late CacheManager manager;
    late CacheRateLimiterBackend backend;
    late TokenBucketConfig bucket;
    late DateTime base;

    setUp(() {
      manager = CacheManager();
      manager.registerStore('rate', {'driver': 'array'});
      final repository = manager.store('rate');
      backend = CacheRateLimiterBackend(repository: repository);
      bucket = buildBucketConfig(
        capacity: 3,
        refillInterval: const Duration(seconds: 30),
      );
      base = DateTime.now();
    });

    tearDown(() async {
      await backend.close();
    });

    test('enforces capacity and allows refill', () async {
      final first = await backend.consume('ip:1', bucket, base);
      final second = await backend.consume('ip:1', bucket, base);
      final third = await backend.consume('ip:1', bucket, base);

      expect(first.allowed, isTrue);
      expect(second.allowed, isTrue);
      expect(third.allowed, isTrue);

      final blocked = await backend.consume('ip:1', bucket, base);
      expect(blocked.allowed, isFalse);

      final afterRefill = await backend.consume(
        'ip:1',
        bucket,
        base.add(const Duration(seconds: 40)),
      );
      expect(afterRefill.allowed, isTrue);
    });

    test('shares state across backends', () async {
      final otherBackend = CacheRateLimiterBackend(
        repository: manager.store('rate'),
      );

      final allowed1 = await backend.consume('user:42', bucket, base);
      final allowed2 = await otherBackend.consume('user:42', bucket, base);
      final allowed3 = await backend.consume('user:42', bucket, base);

      expect(allowed1.allowed, isTrue);
      expect(allowed2.allowed, isTrue);
      expect(allowed3.allowed, isTrue);

      final blocked = await otherBackend.consume('user:42', bucket, base);
      expect(blocked.allowed, isFalse);

      await otherBackend.close();
    });

    test('enforces strict sliding window', () async {
      final windowConfig = SlidingWindowConfig(
        limit: 2,
        window: const Duration(seconds: 30),
      );
      final first = await backend.consume('window:user', windowConfig, base);
      final second = await backend.consume('window:user', windowConfig, base);
      final third = await backend.consume('window:user', windowConfig, base);

      expect(first.allowed, isTrue);
      expect(second.allowed, isTrue);
      expect(third.allowed, isFalse);
      expect(third.retryAfter, greaterThan(Duration.zero));

      final afterWindow = await backend.consume(
        'window:user',
        windowConfig,
        base.add(const Duration(seconds: 35)),
      );
      expect(afterWindow.allowed, isTrue);
    });

    test('resets quotas after period boundary', () async {
      final quotaConfig = QuotaConfig(
        limit: 3,
        period: const Duration(hours: 24),
      );

      final t1 = await backend.consume('quota:user', quotaConfig, base);
      final t2 = await backend.consume('quota:user', quotaConfig, base);
      final t3 = await backend.consume('quota:user', quotaConfig, base);
      final blocked = await backend.consume('quota:user', quotaConfig, base);

      expect(t1.allowed, isTrue);
      expect(t2.allowed, isTrue);
      expect(t3.allowed, isTrue);
      expect(blocked.allowed, isFalse);

      final nextPeriod = await backend.consume(
        'quota:user',
        quotaConfig,
        base.add(const Duration(hours: 25)),
      );
      expect(nextPeriod.allowed, isTrue);
    });

    test('falls back to local enforcement when repository fails', () async {
      final failing = CacheRateLimiterBackend(repository: ThrowingRepository());
      final config = buildBucketConfig(
        capacity: 1,
        refillInterval: const Duration(seconds: 10),
      );

      final first = await failing.consume(
        'fail:user',
        config,
        base,
        failover: RateLimitFailoverMode.local,
      );
      final blocked = await failing.consume(
        'fail:user',
        config,
        base,
        failover: RateLimitFailoverMode.local,
      );

      expect(first.allowed, isTrue);
      expect(first.failoverMode, RateLimitFailoverMode.local);
      expect(blocked.allowed, isFalse);
      expect(blocked.failoverMode, RateLimitFailoverMode.local);

      await failing.close();
    });

    test('honours fail-open mode when backend unavailable', () async {
      final failing = CacheRateLimiterBackend(repository: ThrowingRepository());
      final config = buildBucketConfig(
        capacity: 1,
        refillInterval: const Duration(seconds: 10),
      );

      final outcome = await failing.consume(
        'fail-open:user',
        config,
        base,
        failover: RateLimitFailoverMode.allow,
      );

      expect(outcome.allowed, isTrue);
      expect(outcome.failoverMode, RateLimitFailoverMode.allow);

      await failing.close();
    });

    test('can fail closed when backend unavailable', () async {
      final failing = CacheRateLimiterBackend(repository: ThrowingRepository());
      final config = buildBucketConfig(
        capacity: 1,
        refillInterval: const Duration(seconds: 10),
      );

      final outcome = await failing.consume(
        'fail-closed:user',
        config,
        base,
        failover: RateLimitFailoverMode.block,
      );

      expect(outcome.allowed, isFalse);
      expect(outcome.failoverMode, RateLimitFailoverMode.block);

      await failing.close();
    });
  });
}

class ThrowingRepository implements Repository {
  @override
  FutureOr<dynamic> pull(dynamic key, [dynamic defaultValue]) =>
      throw StateError('unavailable');

  @override
  FutureOr<dynamic> get(String key) => throw StateError('unavailable');

  @override
  FutureOr<bool> put(String key, dynamic value, [Duration? ttl]) =>
      throw StateError('unavailable');

  @override
  FutureOr<bool> add(String key, dynamic value, [Duration? ttl]) =>
      throw StateError('unavailable');

  @override
  FutureOr<dynamic> increment(String key, [dynamic value = 1]) =>
      throw StateError('unavailable');

  @override
  FutureOr<dynamic> decrement(String key, [dynamic value = 1]) =>
      throw StateError('unavailable');

  @override
  FutureOr<bool> forever(String key, dynamic value) =>
      throw StateError('unavailable');

  @override
  FutureOr<dynamic> remember(String key, dynamic ttl, Function callback) =>
      throw StateError('unavailable');

  @override
  FutureOr<dynamic> sear(String key, Function callback) =>
      throw StateError('unavailable');

  @override
  FutureOr<dynamic> rememberForever(String key, Function callback) =>
      throw StateError('unavailable');

  @override
  FutureOr<bool> forget(String key) => throw StateError('unavailable');

  @override
  Store getStore() => _ThrowingStore();
}

class _ThrowingStore implements Store {
  @override
  FutureOr<bool> flush() => throw StateError('unavailable');

  @override
  FutureOr<bool> forget(String key) => throw StateError('unavailable');

  @override
  FutureOr<List<String>> getAllKeys() => throw StateError('unavailable');

  @override
  FutureOr<dynamic> get(String key) => throw StateError('unavailable');

  @override
  String getPrefix() => 'fail';

  @override
  FutureOr<dynamic> increment(String key, [int value = 1]) =>
      throw StateError('unavailable');

  @override
  FutureOr<dynamic> decrement(String key, [int value = 1]) =>
      throw StateError('unavailable');

  @override
  FutureOr<Map<String, dynamic>> many(List<String> keys) =>
      throw StateError('unavailable');

  @override
  FutureOr<bool> put(String key, dynamic value, int seconds) =>
      throw StateError('unavailable');

  @override
  FutureOr<bool> putMany(Map<String, dynamic> values, int seconds) =>
      throw StateError('unavailable');

  @override
  FutureOr<bool> forever(String key, dynamic value) =>
      throw StateError('unavailable');
}
