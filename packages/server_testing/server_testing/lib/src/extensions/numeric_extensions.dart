import 'dart:math' as math;

/// A collection of extension methods for numeric types that provide various
/// mathematical and comparison operations.
///
/// This extension adds functionality to check numeric properties and perform
/// mathematical calculations on numbers. It includes methods for:
/// * Comparison operations (greater than, less than, etc.)
/// * Number properties (even, odd, prime, etc.)
/// * Mathematical operations (square root, power)
///
/// Example usage:
///
/// void main() {
///   int number = 7;
///   print(number.isPositive()); // true
///   print(number.isPrime()); // true
///   print(number.isBetween(1, 10)); // true
/// }
///
extension NumericConditions on num {
  /// Returns whether this number is greater than [value].
  bool isGreaterThan(num value) => this > value;

  /// Returns whether this number is less than [value].
  bool isLessThan(num value) => this < value;

  /// Returns whether this number is greater than or equal to [value].
  bool isGreaterOrEqual(num value) => this >= value;

  /// Returns whether this number is less than or equal to [value].
  bool isLessOrEqual(num value) => this <= value;

  /// Returns whether this number falls within the range [min] to [max], inclusive.
  bool isBetween(num min, num max) => this >= min && this <= max;

  /// Returns whether this number is evenly divisible by [divisor].
  bool isDivisibleBy(num divisor) => this % divisor == 0;

  /// Returns whether this number is a multiple of [factor].
  bool isMultipleOf(num factor) => this / factor % 1 == 0;

  /// Returns whether this number is positive (greater than zero).
  bool isPositive() => this > 0;

  /// Returns whether this number is negative (less than zero).
  bool isNegative() => this < 0;

  /// Returns whether this number is exactly zero.
  bool isZero() => this == 0;

  /// Returns whether this number is even.
  bool isEven() => this % 2 == 0;

  /// Returns whether this number is odd.
  bool isOdd() => this % 2 != 0;

  /// Returns whether this number is prime.
  ///
  /// A prime number is a natural number greater than 1 that is only
  /// divisible by 1 and itself. This implementation uses trial division
  /// with optimization for factors of 2 and 3.
  bool isPrime() {
    if (this <= 1) return false;
    if (this <= 3) return true;
    if (isDivisibleBy(2) || isDivisibleBy(3)) return false;

    for (var i = 5; i * i <= this; i += 6) {
      if (isDivisibleBy(i) || isDivisibleBy(i + 2)) return false;
    }
    return true;
  }

  /// Returns whether this number is a perfect square.
  ///
  /// A perfect square is a number that has an integer square root.
  bool isPerfectSquare() => sqrt() % 1 == 0;

  /// Returns the square root of this number.
  double sqrt() => math.sqrt(toDouble());

  /// Returns this number raised to the power of [exponent].
  num pow(num exponent) => math.pow(this, exponent);
}
