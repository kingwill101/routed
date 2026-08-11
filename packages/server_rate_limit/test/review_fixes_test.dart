import 'dart:async';

import 'package:server_cache/server_cache.dart' as cache;
import 'package:server_contracts/server_contracts.dart' as contracts;
import 'package:server_rate_limit/server_rate_limit.dart';
import 'package:test/test.dart';

class _FakeRequest implements RateLimitRequest {
  _FakeRequest(this.method, this.path);

  @override
  String method;
  @override
  String path;
  @override
  String clientIP = '1.2.3.4';
  @override
  String remoteAddr = '';

  @override
  String header(String name) => '';
}

/// A repository whose underlying store implements LockProvider
/// (ArrayStore from server_cache), matching real distributed setups.
class _LockedRepository implements contracts.Repository {
  final cache.ArrayStore store = cache.ArrayStore();
  final Map<String, dynamic> entries = {};

  @override
  Future<dynamic> get(String key) async => entries[key];

  @override
  Future<bool> put(String key, dynamic value, [Duration? ttl]) async {
    entries[key] = value;
    return true;
  }

  @override
  Future<bool> forget(String key) async {
    entries.remove(key);
    return true;
  }

  @override
  Future<dynamic> pull(dynamic key, [dynamic defaultValue]) async {
    final value = entries[key];
    entries.remove(key);
    return value ?? defaultValue;
  }

  @override
  Future<bool> add(String key, dynamic value, [Duration? ttl]) async {
    final exists = entries.containsKey(key);
    if (!exists) entries[key] = value;
    return !exists;
  }

  @override
  Future<dynamic> increment(String key, [dynamic value = 1]) async {
    final current = entries[key] as num? ?? 0;
    final next = current + (value as num);
    entries[key] = next;
    return next;
  }

  @override
  Future<dynamic> decrement(String key, [dynamic value = 1]) async {
    final current = entries[key] as num? ?? 0;
    final next = current - (value as num);
    entries[key] = next;
    return next;
  }

  @override
  Future<bool> forever(String key, dynamic value) => put(key, value, null);

  @override
  Future<dynamic> remember(String key, dynamic ttl, Function callback) async {
    final value = entries[key];
    if (value != null) return value;
    final result = await callback();
    await put(key, result, ttl is Duration ? ttl : null);
    return result;
  }

  @override
  Future<dynamic> sear(String key, Function callback) =>
      rememberForever(key, callback);

  @override
  Future<dynamic> rememberForever(String key, Function callback) async {
    final value = entries[key];
    if (value != null) return value;
    final result = await callback();
    await put(key, result, null);
    return result;
  }

  @override
  contracts.Store getStore() => store;
}

void main() {
  group('CacheRateLimiterBackend lock acquisition', () {
    test('concurrent consumers are serialized by the cache lock', () async {
      final repository = _LockedRepository();
      final backend = CacheRateLimiterBackend(repository: repository);
      final config = TokenBucketConfig(
        capacity: 1,
        refillTokens: 1,
        refillInterval: const Duration(seconds: 1),
        maxTokens: 1,
      );
      final key = 'bucket';

      final results = await Future.wait([
        backend.consume(key, config, DateTime.now()),
        backend.consume(key, config, DateTime.now()),
        backend.consume(key, config, DateTime.now()),
      ]);

      // With a capacity-1 bucket, exactly one of the three concurrent calls
      // may be allowed; the others must be blocked.
      final allowedCount = results.where((r) => r.allowed).length;
      expect(allowedCount, 1,
          reason: 'the lock must make the read-modify-write atomic');
    });
  });

  group('RequestMatcher method enforcement for catch-all patterns', () {
    test('catch-all "*" still honours the configured method', () {
      final matcher = RequestMatcher(method: 'GET', pattern: '*');

      expect(matcher.matches(_FakeRequest('GET', '/anything')), isTrue);
      expect(matcher.matches(_FakeRequest('POST', '/anything')), isFalse,
          reason: 'a GET-only policy must not match POST traffic');
      expect(matcher.matches(_FakeRequest('get', '/anything')), isTrue,
          reason: 'method comparison must be case-insensitive');
    });

    test('empty pattern honours the configured method', () {
      final matcher = RequestMatcher(method: 'POST', pattern: '');

      expect(matcher.matches(_FakeRequest('POST', '/x')), isTrue);
      expect(matcher.matches(_FakeRequest('GET', '/x')), isFalse);
    });

    test('unrestricted catch-all matches every method', () {
      final matcher = RequestMatcher(method: null, pattern: '*');
      expect(matcher.matches(_FakeRequest('DELETE', '/x')), isTrue);
      expect(matcher.matches(_FakeRequest('PATCH', '/x')), isTrue);
    });

    test('wildcard patterns still enforce the method', () {
      final matcher = RequestMatcher(method: 'GET', pattern: '/api/**');
      expect(matcher.matches(_FakeRequest('GET', '/api/users')), isTrue);
      expect(matcher.matches(_FakeRequest('POST', '/api/users')), isFalse);
      expect(matcher.matches(_FakeRequest('GET', '/other')), isFalse);
    });
  });
}