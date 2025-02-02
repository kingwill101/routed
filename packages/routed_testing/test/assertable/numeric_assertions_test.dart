import 'package:routed_testing/src/extensions/numeric_assertions.dart';
import 'package:test/test.dart';

void main() {
  group('NumericAssertions', () {
    test('basic assertions', () {
      25.assertGreaterThan(20);
      15.assertLessThan(20);
      25.assertGreaterOrEqual(25);
      15.assertLessOrEqual(15);

      expect(() => 15.assertGreaterThan(20), throwsA(isA<TestFailure>()));
    });

    test('range assertions', () {
      25.assertBetween(20, 30);

      expect(() => 15.assertBetween(20, 30), throwsA(isA<TestFailure>()));
    });

    test('mathematical assertions', () {
      100.assertDivisibleBy(10);
      25.assertMultipleOf(5);
      25.assertPerfectSquare();

      expect(() => 25.assertDivisibleBy(7), throwsA(isA<TestFailure>()));
    });

    test('sign assertions', () {
      25.assertPositive();
      (-25).assertNegative();
      0.assertZero();

      expect(() => (-25).assertPositive(), throwsA(isA<TestFailure>()));
    });

    test('number property assertions', () {
      24.assertEven();
      25.assertOdd();
      17.assertPrime();

      expect(() => 24.assertOdd(), throwsA(isA<TestFailure>()));
    });

    test('custom error messages', () {
      expect(() => 15.assertGreaterThan(20, message: 'Custom error'),
          throwsA(isA<TestFailure>()));
    });
    test('chaining assertions', () {
      final number = 25;
      number
        ..assertGreaterThan(20)
        ..assertBetween(20, 30)
        ..assertPerfectSquare();
    });
  });
}
