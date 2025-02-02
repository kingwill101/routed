import 'package:routed_testing/src/assertable_json/assertable_json.dart';
import 'package:test/test.dart';

void main() {
  group('AssertableJson', () {
    test('Constructor initializes json correctly', () {
      final data = {'key': 'value'};
      final assertableJson = AssertableJson(data);
      expect(assertableJson.json, equals(data));
    });
  });
}
