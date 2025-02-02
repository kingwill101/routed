import 'package:test/test.dart';
import 'package:routed_testing/src/assertable_json/assertable_json.dart';

void main() {
  group('ConditionMixin', () {
    late AssertableJson json;

    setUp(() {
      json = AssertableJson({
        'age': 25,
        'score': 95.5,
        'count': 100,
        'temperature': -10,
        'price': 49.99
      });
    });

    test('isGreaterThan validates numeric comparisons', () {
      json.isGreaterThan('age', 18);
      json.isGreaterThan('score', 90);

      expect(
        () => json.isGreaterThan('age', 30),
        throwsA(isA<TestFailure>()),
      );
    });

    test('isLessThan validates numeric comparisons', () {
      json.isLessThan('age', 30);
      json.isLessThan('score', 100);

      expect(
        () => json.isLessThan('age', 20),
        throwsA(isA<TestFailure>()),
      );
    });

    test('isGreaterOrEqual validates inclusive comparisons', () {
      json.isGreaterOrEqual('age', 25);
      json.isGreaterOrEqual('age', 24);

      expect(
        () => json.isGreaterOrEqual('age', 26),
        throwsA(isA<TestFailure>()),
      );
    });

    test('isLessOrEqual validates inclusive comparisons', () {
      json.isLessOrEqual('age', 25);
      json.isLessOrEqual('age', 26);

      expect(
        () => json.isLessOrEqual('age', 24),
        throwsA(isA<TestFailure>()),
      );
    });

    test('equals validates exact numeric equality', () {
      json.equals('age', 25);
      json.equals('score', 95.5);

      expect(
        () => json.equals('age', 26),
        throwsA(isA<TestFailure>()),
      );
    });

    test('notEquals validates numeric inequality', () {
      json.notEquals('age', 26);
      json.notEquals('score', 95);

      expect(
        () => json.notEquals('age', 25),
        throwsA(isA<TestFailure>()),
      );
    });

    test('isDivisibleBy validates division without remainder', () {
      json.isDivisibleBy('count', 10);
      json.isDivisibleBy('count', 25);

      expect(
        () => json.isDivisibleBy('count', 7),
        throwsA(isA<TestFailure>()),
      );
    });

    test('isMultipleOf validates multiplication factors', () {
      json.isMultipleOf('count', 10);
      json.isMultipleOf('count', 25);

      expect(
        () => json.isMultipleOf('count', 7),
        throwsA(isA<TestFailure>()),
      );
    });

    test('isBetween validates numeric ranges', () {
      json.isBetween('age', 20, 30);
      json.isBetween('score', 90, 100);

      expect(
        () => json.isBetween('age', 26, 30),
        throwsA(isA<TestFailure>()),
      );
    });

    test('isPositive validates positive numbers', () {
      json.isPositive('age');
      json.isPositive('score');

      expect(
        () => json.isPositive('temperature'),
        throwsA(isA<TestFailure>()),
      );
    });

    test('isNegative validates negative numbers', () {
      json.isNegative('temperature');

      expect(
        () => json.isNegative('age'),
        throwsA(isA<TestFailure>()),
      );
    });

    test('handles non-numeric values appropriately', () {
      final invalidJson = AssertableJson({'text': 'not a number'});

      expect(
        () => invalidJson.isGreaterThan('text', 10),
        throwsA(isA<TestFailure>()),
      );
    });

    test('handles missing keys appropriately', () {
      expect(
        () => json.isGreaterThan('nonexistent', 10),
        throwsA(isA<TestFailure>()),
      );
    });

    test('chaining multiple conditions', () {
      json
          .isGreaterThan('age', 20)
          .isLessThan('age', 30)
          .equals('count', 100)
          .isBetween('score', 90, 100)
          .isPositive('price');
    });
  });
}
