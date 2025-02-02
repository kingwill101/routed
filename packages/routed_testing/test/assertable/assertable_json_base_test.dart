import 'package:routed_testing/src/assertable_json/assertable_json.dart';
import 'package:test/test.dart';

void main() {
  group('AssertableJsonBase', () {
    test('scope with valid key', () {
      final data = {
        'nested': {'key': 'value'}
      };
      final json = AssertableJson(data);

      json.scope('nested', (scope) {
        scope.where('key', 'value').etc();
      });
    });

    test('scope with invalid key', () {
      final data = {'key': 'value'};
      final json = AssertableJson(data);

      expect(
        () => json.scope('invalid', (scope) {}).etc(),
        throwsA(isA<TestFailure>()),
      );
    });

    test('first on non-empty json', () {
      final data = {
        'firstKey': {'value': 'first'},
        'secondKey': {'value': 'second'}
      };
      final json = AssertableJson(data);

      json.first((firstJson) {
        firstJson.where('value', 'first').etc();
      });
    });

    test('first on empty json', () {
      final data = {};
      final json = AssertableJson(data);

      expect(
        () => json.first((firstJson) {}),
        throwsA(isA<TestFailure>()),
      );
    });

    test('each iterates over array elements', () {
      final data = {
        'items': [
          {'id': 1, 'name': 'first'},
          {'id': 2, 'name': 'second'}
        ]
      };
      final json = AssertableJson(data);
      final ids = [];
      final names = [];

      json.scope('items', (scope) {
        scope.each((item) {
          ids.add(item.get('id'));
          names.add(item.get('name'));
        }).etc();
      });

      expect(ids, equals([1, 2]));
      expect(names, equals(['first', 'second']));
    });

    test('each iterates over object properties', () {
      final data = {
        'key1': {'value': 'first'},
        'key2': {'value': 'second'}
      };
      final json = AssertableJson(data);
      final values = [];

      json.each((item) {
        values.add(item.get('value'));
        item.etc(); // Mark all properties as interacted
      }); // Mark root properties as interacted

      expect(values, equals(['first', 'second']));
    });
  });
}
