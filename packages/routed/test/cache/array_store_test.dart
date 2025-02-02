import 'package:routed/src/cache/array_store.dart';
import 'package:routed/src/contracts/cache/store.dart';
import 'package:test/test.dart';

void main() {
  group('ArrayStore Tests', () {
    late Store store;

    setUp(() {
      store = ArrayStore();
    });

    test('put and get item', () async {
      await store.put('key', 'value', 60);
      final value = await store.get('key');
      expect(value, 'value');
    });

    test('put and forget item', () async {
      await store.put('key', 'value', 60);
      await store.forget('key');
      final value = await store.get('key');
      expect(value, isNull);
    });

    test('increment and decrement item', () async {
      await store.put('counter', 1, 60);
      await store.increment('counter', 1);
      var value = await store.get('counter');
      expect(value, 2);

      await store.decrement('counter', 1);
      value = await store.get('counter');
      expect(value, 1);
    });

    test('put item forever', () async {
      await store.forever('key', 'value');
      final value = await store.get('key');
      expect(value, 'value');
    });

    test('flush all items', () async {
      await store.put('key1', 'value1', 60);
      await store.put('key2', 'value2', 60);
      await store.flush();
      final value1 = await store.get('key1');
      final value2 = await store.get('key2');
      expect(value1, isNull);
      expect(value2, isNull);
    });

    test('get multiple items', () async {
      await store.put('key1', 'value1', 60);
      await store.put('key2', 'value2', 60);
      final values = await store.many(['key1', 'key2', 'key3']);
      expect(values['key1'], 'value1');
      expect(values['key2'], 'value2');
      expect(values['key3'], isNull);
    });
  });
}
