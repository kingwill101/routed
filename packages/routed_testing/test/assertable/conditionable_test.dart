import 'package:routed_testing/src/assertable_json/assertable_json.dart';
import 'package:test/test.dart';

void main() {
  group('ConditionableMixin', () {
    test('when executes callback when condition is true', () {
      final json = AssertableJson({'key': 'value'});
      var callbackExecuted = false;

      json.when(true, (_) => callbackExecuted = true);
      expect(callbackExecuted, isTrue);
    });

    test('when skips callback when condition is false', () {
      final json = AssertableJson({'key': 'value'});
      var callbackExecuted = false;

      json.when(false, (_) => callbackExecuted = true);
      expect(callbackExecuted, isFalse);
    });

    test('unless executes callback when condition is false', () {
      final json = AssertableJson({'key': 'value'});
      var callbackExecuted = false;

      json.unless(false, (_) => callbackExecuted = true);
      expect(callbackExecuted, isTrue);
    });
  });
}
