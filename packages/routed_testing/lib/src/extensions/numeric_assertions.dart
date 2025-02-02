import 'dart:math';

import 'package:test/test.dart';

/// Extension providing assertion methods for numeric values.
///
/// This extension adds various assertion methods to [num] types to help with
/// testing numeric conditions. Each method performs a specific validation and
/// throws a test failure if the condition is not met.
///
/// Example usage:
///
/// ```dart
/// void main() {
///   test('numeric assertions', () {
///     5.assertGreaterThan(3);
///     10.assertDivisibleBy(2);
///     7.assertPrime();
///   });
/// }
/// ```
///
extension NumericAssertions on num {
  /// Asserts that this number is greater than [value].
  ///
  /// Throws a test failure if this number is not greater than [value].
  ///
  /// - [value]: The value to compare against.
  /// - [message]: Optional custom message for the failure reason.
  void assertGreaterThan(num value, {String? message}) {
    expect(this > value, isTrue,
        reason: message ?? 'Expected $this to be greater than $value');
  }

  /// Asserts that this number is less than [value].
  ///
  /// Throws a test failure if this number is not less than [value].
  ///
  /// - [value]: The value to compare against.
  /// - [message]: Optional custom message for the failure reason.
  void assertLessThan(num value, {String? message}) {
    expect(this < value, isTrue,
        reason: message ?? 'Expected $this to be less than $value');
  }

  /// Asserts that this number is greater than or equal to [value].
  ///
  /// Throws a test failure if this number is not greater than or equal to [value].
  ///
  /// - [value]: The value to compare against.
  /// - [message]: Optional custom message for the failure reason.
  void assertGreaterOrEqual(num value, {String? message}) {
    expect(this >= value, isTrue,
        reason:
            message ?? 'Expected $this to be greater than or equal to $value');
  }

  /// Asserts that this number is less than or equal to [value].
  ///
  /// Throws a test failure if this number is not less than or equal to [value].
  ///
  /// - [value]: The value to compare against.
  /// - [message]: Optional custom message for the failure reason.
  void assertLessOrEqual(num value, {String? message}) {
    expect(this <= value, isTrue,
        reason: message ?? 'Expected $this to be less than or equal to $value');
  }

  /// Asserts that this number is between [min] and [max] (inclusive).
  ///
  /// Throws a test failure if this number is not between [min] and [max].
  ///
  /// - [min]: The minimum value of the range.
  /// - [max]: The maximum value of the range.
  /// - [message]: Optional custom message for the failure reason.
  void assertBetween(num min, num max, {String? message}) {
    expect(this >= min && this <= max, isTrue,
        reason: message ?? 'Expected $this to be between $min and $max');
  }

  /// Asserts that this number is evenly divisible by [divisor].
  ///
  /// Throws a test failure if this number is not evenly divisible by [divisor].
  ///
  /// - [divisor]: The number to divide by.
  /// - [message]: Optional custom message for the failure reason.
  void assertDivisibleBy(num divisor, {String? message}) {
    expect(this % divisor == 0, isTrue,
        reason: message ?? 'Expected $this to be divisible by $divisor');
  }

  /// Asserts that this number is a multiple of [factor].
  ///
  /// Throws a test failure if this number is not a multiple of [factor].
  ///
  /// - [factor]: The factor to check against.
  /// - [message]: Optional custom message for the failure reason.
  void assertMultipleOf(num factor, {String? message}) {
    expect(this / factor % 1 == 0, isTrue,
        reason: message ?? 'Expected $this to be a multiple of $factor');
  }

  /// Asserts that this number is positive (greater than zero).
  ///
  /// Throws a test failure if this number is not positive.
  ///
  /// - [message]: Optional custom message for the failure reason.
  void assertPositive({String? message}) {
    expect(this > 0, isTrue,
        reason: message ?? 'Expected $this to be positive');
  }

  /// Asserts that this number is negative (less than zero).
  ///
  /// Throws a test failure if this number is not negative.
  ///
  /// - [message]: Optional custom message for the failure reason.
  void assertNegative({String? message}) {
    expect(this < 0, isTrue,
        reason: message ?? 'Expected $this to be negative');
  }

  /// Asserts that this number is exactly zero.
  ///
  /// Throws a test failure if this number is not zero.
  ///
  /// - [message]: Optional custom message for the failure reason.
  void assertZero({String? message}) {
    expect(this == 0, isTrue, reason: message ?? 'Expected $this to be zero');
  }

  /// Asserts that this number is even.
  ///
  /// Throws a test failure if this number is not even.
  ///
  /// - [message]: Optional custom message for the failure reason.
  void assertEven({String? message}) {
    expect(this % 2 == 0, isTrue,
        reason: message ?? 'Expected $this to be even');
  }

  /// Asserts that this number is odd.
  ///
  /// Throws a test failure if this number is not odd.
  ///
  /// - [message]: Optional custom message for the failure reason.
  void assertOdd({String? message}) {
    expect(this % 2 != 0, isTrue,
        reason: message ?? 'Expected $this to be odd');
  }

  /// Asserts that this number is prime.
  ///
  /// A prime number is a natural number greater than 1 that is only divisible by 1 and itself.
  /// This method uses trial division to check primality.
  ///
  /// Throws a test failure if this number is not prime.
  ///
  /// - [message]: Optional custom message for the failure reason.
  void assertPrime({String? message}) {
    if (this <= 1) {
      fail(message ?? '$this is not prime');
    }
    if (this <= 3) return;
    if (this % 2 == 0 || this % 3 == 0) {
      fail(message ?? '$this is not prime');
    }

    for (var i = 5; i * i <= this; i += 6) {
      if (this % i == 0 || this % (i + 2) == 0) {
        fail(message ?? '$this is not prime');
      }
    }
  }

  /// Asserts that this number is a perfect square.
  ///
  /// A perfect square is an integer that is the square of another integer.
  ///
  /// Throws a test failure if this number is not a perfect square.
  ///
  /// - [message]: Optional custom message for the failure reason.
  void assertPerfectSquare({String? message}) {
    expect(sqrt(this) % 1 == 0, isTrue,
        reason: message ?? 'Expected $this to be a perfect square');
  }
}
