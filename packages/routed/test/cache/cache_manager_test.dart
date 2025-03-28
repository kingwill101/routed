import 'package:routed/src/cache/cache_manager.dart';
import 'package:routed/src/cache/array_store_factory.dart';
import 'package:routed/src/cache/file_store_factory.dart';
import 'package:test/test.dart';
import 'dart:io';

void main() {
  group('CacheManager Tests', () {
    late CacheManager cacheManager;

    setUp(() {
      cacheManager = CacheManager();
      cacheManager.registerStoreFactory('array', ArrayStoreFactory());
      cacheManager.registerStoreFactory('file', FileStoreFactory());
    });

    test('store and retrieve from array store', () async {
      cacheManager.registerStore('array', {'driver': 'array'});
      final repository = cacheManager.store('array');
      await repository.put('key', 'value', Duration(seconds: 60));
      final value = await repository.pull('key');
      expect(value, 'value');
    });

    test('store and retrieve from file store', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      cacheManager.registerStore('file', {
        'driver': 'file',
        'path': tempDir.path,
        'permission': null,
      });
      final repository = cacheManager.store('file');
      await repository.put('key', 'value', Duration(seconds: 60));
      final value = await repository.pull('key');
      expect(value, 'value');
      tempDir.deleteSync(recursive: true);
    });

    test('increment and decrement in array store', () async {
      cacheManager.registerStore('array', {'driver': 'array'});
      final repository = cacheManager.store('array');
      await repository.put('counter', 1, Duration(seconds: 60));
      await repository.increment('counter', 1);
      var value = await repository.pull('counter');
      expect(value, 2);

      await repository.put('counter', 1, Duration(seconds: 60));
      await repository.decrement('counter', 1);
      value = await repository.pull('counter');
      expect(value, 0);
    });

    test('increment and decrement in file store', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      cacheManager.registerStore('file', {
        'driver': 'file',
        'path': tempDir.path,
        'permission': null,
      });
      final repository = cacheManager.store('file');
      await repository.put('counter', 1, Duration(seconds: 60));
      await repository.increment('counter', 1);
      var value = await repository.pull('counter');
      expect(value, 2);

      await repository.put('counter', 1, Duration(seconds: 60));
      await repository.decrement('counter', 1);
      value = await repository.pull('counter');
      expect(value, 0);
      tempDir.deleteSync(recursive: true);
    });

    test('flush all items in array store', () async {
      cacheManager.registerStore('array', {'driver': 'array'});
      final repository = cacheManager.store('array');
      await repository.put('key1', 'value1', Duration(seconds: 60));
      await repository.put('key2', 'value2', Duration(seconds: 60));
      await repository.getStore().flush();
      final value1 = await repository.pull('key1');
      final value2 = await repository.pull('key2');
      expect(value1, isNull);
      expect(value2, isNull);
    });

    test('flush all items in file store', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      cacheManager.registerStore('file', {
        'driver': 'file',
        'path': tempDir.path,
        'permission': null,
      });
      final repository = cacheManager.store('file');
      await repository.put('key1', 'value1', Duration(seconds: 60));
      await repository.put('key2', 'value2', Duration(seconds: 60));
      await repository.getStore().flush();
      final value1 = await repository.pull('key1');
      final value2 = await repository.pull('key2');
      expect(value1, isNull);
      expect(value2, isNull);
      tempDir.deleteSync(recursive: true);
    });
  });
}
