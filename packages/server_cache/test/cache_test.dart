import 'package:server_cache/server_cache.dart';
import 'package:test/test.dart';

void main() {
  group('Cache operations via DataCacheManager', () {
    late DataCacheManager cacheManager;

    setUp(() {
      cacheManager = DataCacheManager();
      cacheManager.registerStore('array', {'driver': 'array'});
    });

    test('basic put and get', () async {
      final repo = cacheManager.store('array');
      await repo.put('test-key', 'test-value', const Duration(seconds: 60));
      final value = await repo.get('test-key');
      expect(value, equals('test-value'));
    });

    test('increment and decrement operations', () async {
      final repo = cacheManager.store('array');
      await repo.put('counter', 0, const Duration(seconds: 60));
      await repo.increment('counter', 5);
      await repo.decrement('counter', 2);
      final value = await repo.get('counter');
      expect(value, equals(3));
    });

    test('remember cache operation', () async {
      final repo = cacheManager.store('array');
      final value = await repo.remember(
        'remembered-key',
        const Duration(seconds: 60),
        () async => 'computed-value',
      );
      expect(value, equals('computed-value'));

      // Second remember should return cached value, not recompute.
      final cached = await repo.remember(
        'remembered-key',
        const Duration(seconds: 60),
        () async => 'other-value',
      );
      expect(cached, equals('computed-value'));
    });

    test('pull removes value', () async {
      final repo = cacheManager.store('array');
      await repo.put('pull-key', 'to-be-pulled');
      final pulled = await repo.pull('pull-key');
      expect(pulled, equals('to-be-pulled'));
      expect(await repo.get('pull-key'), isNull);
    });
  });
}
