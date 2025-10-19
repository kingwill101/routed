import 'package:routed/routed.dart';
import 'package:test/test.dart';

void main() {
  group('Cache events', () {
    test('publishes hit, miss, write, and forget events', () async {
      final engine = Engine(
        configItems: {
          'cache': {
            'default': 'array',
            'stores': {
              'array': {'driver': 'array'},
            },
          },
        },
      );
      addTearDown(() async => await engine.close());
      await engine.initialize();

      final eventManager = await engine.make<EventManager>();
      final received = <CacheEvent>[];
      final subscription = eventManager.on<CacheEvent>().listen(received.add);
      addTearDown(subscription.cancel);

      final cacheManager = await engine.make<CacheManager>();
      final repository = cacheManager.store('array');

      await repository.put('demo', 'value');
      await repository.pull('demo');
      await repository.pull('demo');
      await repository.remember(
        'demo',
        const Duration(seconds: 30),
        () async => 'fresh',
      );
      await repository.remember(
        'demo',
        const Duration(seconds: 30),
        () async => 'skip',
      );

      await Future<void>.delayed(Duration.zero);

      expect(
        received.whereType<CacheWriteEvent>(),
        isNotEmpty,
        reason: 'expected write events when putting values',
      );
      expect(
        received.whereType<CacheHitEvent>(),
        isNotEmpty,
        reason: 'expected hit events for cached values',
      );
      expect(
        received.whereType<CacheMissEvent>(),
        isNotEmpty,
        reason: 'expected miss events for missing values',
      );
      expect(
        received.whereType<CacheForgetEvent>(),
        isNotEmpty,
        reason: 'expected forget events when pulling values',
      );

      final stores = received.map((event) => event.store).toSet();
      expect(stores, equals({'array'}));
    });
  });
}
