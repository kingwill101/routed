import 'package:routed_testing/src/assertable_json/assertable_json.dart';
import 'package:test/test.dart';

void main() {
  group('HasMixin', () {
    test('count verifies list length', () {
      final json = AssertableJson({
        'list': [1, 2, 3]
      });

      json.count('list', 3);
    });

    test('countBetween verifies list length range', () {
      final json = AssertableJson({
        'list': [1, 2, 3]
      });

      json.countBetween('list', 2, 4);
    });

    test('has verifies key existence', () {
      final json = AssertableJson({'key': 'value'});
      json.has('key');
    });

    test('hasNested verifies nested key existence', () {
      final json = AssertableJson({
        'parent': {'child': 'value'}
      });

      json.hasNested('parent.child');
    });

    test('hasAll verifies multiple keys exist', () {
      final json = AssertableJson({'key1': 'value1', 'key2': 'value2'});

      json.hasAll(['key1', 'key2']);
    });

    test('missing verifies key does not exist', () {
      final json = AssertableJson({'key': 'value'});
      json.missing('nonexistent');
    });
  });
}
