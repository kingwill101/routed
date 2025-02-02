import 'package:routed_testing/src/extensions/numeric_extensions.dart';
import 'package:test/test.dart';

void main() {
  group('NumericConditions', () {
    test('basic comparisons', () {
      expect(25.isGreaterThan(20), isTrue);
      expect(15.isLessThan(20), isTrue);
      expect(25.isGreaterOrEqual(25), isTrue);
      expect(15.isLessOrEqual(15), isTrue);
    });

    test('range checks', () {
      expect(25.isBetween(20, 30), isTrue);
      expect(15.isBetween(10, 20), isTrue);
    });

    test('mathematical properties', () {
      expect(100.isDivisibleBy(10), isTrue);
      expect(25.isMultipleOf(5), isTrue);
      expect(25.isPerfectSquare(), isTrue);
    });

    test('sign checks', () {
      expect(25.isPositive(), isTrue);
      expect((-25).isNegative, isTrue);
      expect(0.isZero(), isTrue);
    });

    test('number properties', () {
      expect(24.isEven, isTrue);
      expect(25.isOdd, isTrue);
      expect(17.isPrime(), isTrue);
      expect(25.sqrt(), equals(5));
      expect(5.pow(2), equals(25));
    });

    test('chaining through variables', () {
      final number = 25;
      expect(
          number.isGreaterThan(20) &&
              number.isBetween(20, 30) &&
              number.isPerfectSquare(),
          isTrue);
    });
  });
}
