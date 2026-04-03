import 'package:server_contracts/server_contracts.dart' show Store;
import 'package:server_data/server_data.dart';
import 'package:test/test.dart';

class _CapturingStoreFactory implements StoreFactory {
  Map<String, dynamic>? lastConfig;

  @override
  Store create(Map<String, dynamic> config) {
    lastConfig = Map<String, dynamic>.from(config);
    return ArrayStore();
  }
}

void main() {
  group('DataCacheManager', () {
    test('registers built-in factories by default', () {
      final manager = DataCacheManager();

      expect(manager.hasStoreFactory('array'), isTrue);
      expect(manager.hasStoreFactory('file'), isTrue);
      expect(manager.hasStoreFactory('null'), isTrue);
      expect(manager.hasStoreFactory('redis'), isTrue);
    });

    test('registerStore/store resolve through registered factory', () async {
      final manager = DataCacheManager(registerDefaultStoreFactories: false);
      manager.registerStoreFactory('array', ArrayStoreFactory());
      manager.registerStore('default', {'driver': 'array'});

      final repository = manager.store('default');
      await repository.put('foo', 'bar', const Duration(seconds: 60));

      expect(await repository.get('foo'), equals('bar'));
      expect(manager.hasStore('default'), isTrue);
      expect(manager.storeNames, contains('default'));
      expect(manager.getDefaultDriver(), equals('default'));
    });

    test('setPrefix updates resolved repositories', () async {
      final manager = DataCacheManager(registerDefaultStoreFactories: false);
      manager.registerStoreFactory('array', ArrayStoreFactory());
      manager.registerStore('default', {'driver': 'array'});

      final repository = manager.store('default');
      manager.setPrefix('app:');
      await repository.put('token', 'abc', const Duration(seconds: 60));

      final rawStore = repository.getStore();
      expect(await rawStore.get('app:token'), equals('abc'));
      expect(manager.prefix, equals('app:'));
    });

    test('setCallbacksBuilder applies to resolved repositories', () async {
      final manager = DataCacheManager(registerDefaultStoreFactories: false);
      manager.registerStoreFactory('array', ArrayStoreFactory());
      manager.registerStore('default', {'driver': 'array'});

      final repository = manager.store('default');

      var hits = 0;
      var misses = 0;
      var writes = 0;
      var forgets = 0;
      manager.setCallbacksBuilder(
        (storeName) => RepositoryEventCallbacks(
          onHit: (_) => hits += 1,
          onMiss: (_) => misses += 1,
          onWrite: (_, _) => writes += 1,
          onForget: (_) => forgets += 1,
        ),
      );

      await repository.get('missing');
      await repository.put('k', 'v', const Duration(seconds: 60));
      await repository.get('k');
      await repository.forget('k');

      expect(misses, equals(1));
      expect(writes, equals(1));
      expect(hits, equals(1));
      expect(forgets, equals(1));
    });

    test('config resolver is applied before factory create', () {
      final factory = _CapturingStoreFactory();
      final manager = DataCacheManager(
        registerDefaultStoreFactories: false,
        configResolver: (driver, config) => <String, dynamic>{
          ...config,
          'resolved': true,
        },
      );
      manager
        ..registerStoreFactory('custom', factory)
        ..registerStore('default', {'driver': 'custom', 'foo': 'bar'});

      manager.store('default');

      expect(factory.lastConfig, isNotNull);
      expect(factory.lastConfig!['driver'], equals('custom'));
      expect(factory.lastConfig!['foo'], equals('bar'));
      expect(factory.lastConfig!['resolved'], isTrue);
    });

    test('registerStore supports explicit repository instance', () async {
      final manager = DataCacheManager(registerDefaultStoreFactories: false);
      final provided = RepositoryImpl(ArrayStore(), 'manual', '');
      manager.registerStore('manual', {
        'driver': 'does-not-matter',
      }, repository: provided);

      final resolved = manager.store('manual');
      expect(identical(resolved, provided), isTrue);

      await resolved.put('id', 42, const Duration(seconds: 60));
      expect(await resolved.get('id'), equals(42));
    });

    test('clearResolvedStores keeps config but drops cached repositories', () {
      final manager = DataCacheManager(registerDefaultStoreFactories: false)
        ..registerStoreFactory('array', ArrayStoreFactory())
        ..registerStore('default', {'driver': 'array'});

      final first = manager.store('default');
      manager.clearResolvedStores();
      final second = manager.store('default');

      expect(identical(first, second), isFalse);
      expect(manager.hasStore('default'), isTrue);
    });

    test('throws for missing store configuration', () {
      final manager = DataCacheManager();
      expect(
        () => manager.store('missing'),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('Cache store [missing] is not defined'),
          ),
        ),
      );
    });
  });
}
