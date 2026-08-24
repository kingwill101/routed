import 'package:server_cache/server_cache.dart';
import 'package:test/test.dart';

void main() {
  group('Cache repository behavior', () {
    late DataCacheManager cacheManager;

    setUp(() {
      cacheManager = DataCacheManager()..registerStore('array', ArrayStore());
    });

    test('put, pull and remember simulate cache events', () async {
      final repo = cacheManager.store('array');

      // Write
      await repo.put('demo', 'value');
      expect(await repo.get('demo'), equals('value'));

      // Pull should return and remove
      final pulled = await repo.pull('demo');
      expect(pulled, equals('value'));
      expect(await repo.get('demo'), isNull);

      // Remember with miss then hit
      final fresh = await repo.remember(
        'demo',
        const Duration(seconds: 30),
        () async => 'fresh',
      );
      expect(fresh, equals('fresh'));

      final cached = await repo.remember(
        'demo',
        const Duration(seconds: 30),
        () async => 'skip',
      );
      expect(cached, equals('fresh'));
      expect(await repo.get('demo'), equals('fresh'));
    });
  });
}
