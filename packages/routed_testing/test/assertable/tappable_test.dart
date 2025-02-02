import 'package:routed_testing/src/assertable_json/assertable_json.dart';
import 'package:test/test.dart';

void main() {
  group('TappableMixin', () {
    test('tap executes callback and returns instance', () {
      final json = AssertableJson({'key': 'value'});
      var callbackExecuted = false;

      final result = json.tap((_) => callbackExecuted = true);

      expect(callbackExecuted, isTrue);
      expect(result, equals(json));
    });
  });
}
