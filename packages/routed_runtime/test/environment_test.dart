import 'package:routed_runtime/routed_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('Environment', () {
    test('fromMap supports get/set/remove/contains', () {
      final local = Environment.fromMap({'A': '1'});

      expect(local.get('A'), equals('1'));
      expect(local.containsKey('A'), isTrue);

      local.set('B', '2');
      expect(local['B'], equals('2'));

      local.remove('A');
      expect(local.containsKey('A'), isFalse);

      final map = local.toMap();
      expect(map, containsPair('B', '2'));
    });

    test('global env allows in-memory override', () {
      const key = 'ROUTED_RUNTIME_TEST_KEY';
      env[key] = 'value';
      expect(env[key], equals('value'));
      env.remove(key);
    });
  });
}
