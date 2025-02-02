import 'package:routed_testing/src/extensions/numeric_assertions.dart';
import 'package:test/test.dart';
import 'assertable_json_base.dart';
import 'assertable_json.dart';

/// A mixin that provides numeric comparison and validation methods for JSON properties.
///
/// This mixin extends [AssertableJsonBase] to add methods for asserting numeric
/// conditions on JSON values. It supports various numeric comparisons and validations
/// including:
/// * Greater/less than comparisons
/// * Equality checks
/// * Divisibility tests
/// * Range validation
/// * Sign checking
///
/// Example usage:
///
/// final json = AssertableJson({'value': 42});
/// json.isGreaterThan('value', 40)
///     .isLessThan('value', 50)
///     .isPositive('value');
///
mixin ConditionMixin on AssertableJsonBase {
  /// Asserts that the numeric value at [key] is greater than [value].
  AssertableJson isGreaterThan(String key, num value) {
    final actual = getRequired<num>(key);
    actual.assertGreaterThan(value);
    interactsWith(key);
    return this as AssertableJson;
  }

  /// Asserts that the numeric value at [key] is less than [value].
  AssertableJson isLessThan(String key, num value) {
    final actual = getRequired<num>(key);
    actual.assertLessThan(value);
    interactsWith(key);
    return this as AssertableJson;
  }

  /// Asserts that the numeric value at [key] is greater than or equal to [value].
  AssertableJson isGreaterOrEqual(String key, num value) {
    final actual = getRequired<num>(key);
    actual.assertGreaterOrEqual(value);
    interactsWith(key);
    return this as AssertableJson;
  }

  /// Asserts that the numeric value at [key] is less than or equal to [value].
  AssertableJson isLessOrEqual(String key, num value) {
    final actual = getRequired<num>(key);
    actual.assertLessOrEqual(value);
    interactsWith(key);
    return this as AssertableJson;
  }

  /// Asserts that the numeric value at [key] equals [value].
  AssertableJson equals(String key, num value) {
    final actual = getRequired<num>(key);
    expect(actual == value, isTrue,
        reason: 'Property [$key] is not equal to $value');
    interactsWith(key);
    return this as AssertableJson;
  }

  /// Asserts that the numeric value at [key] does not equal [value].
  AssertableJson notEquals(String key, num value) {
    final actual = getRequired<num>(key);
    expect(actual != value, isTrue,
        reason: 'Property [$key] should not equal $value');
    interactsWith(key);
    return this as AssertableJson;
  }

  /// Asserts that the numeric value at [key] is divisible by [divisor].
  AssertableJson isDivisibleBy(String key, num divisor) {
    final actual = getRequired<num>(key);
    actual.assertDivisibleBy(divisor);
    interactsWith(key);
    return this as AssertableJson;
  }

  /// Asserts that the numeric value at [key] is a multiple of [factor].
  AssertableJson isMultipleOf(String key, num factor) {
    final actual = getRequired<num>(key);
    actual.assertMultipleOf(factor);
    interactsWith(key);
    return this as AssertableJson;
  }

  /// Asserts that the numeric value at [key] is between [min] and [max] inclusive.
  AssertableJson isBetween(String key, num min, num max) {
    final actual = getRequired<num>(key);
    actual.assertBetween(min, max);
    interactsWith(key);
    return this as AssertableJson;
  }

  /// Asserts that the numeric value at [key] is positive (greater than zero).
  AssertableJson isPositive(String key) {
    final actual = getRequired<num>(key);
    actual.assertPositive();
    interactsWith(key);
    return this as AssertableJson;
  }

  /// Asserts that the numeric value at [key] is negative (less than zero).
  AssertableJson isNegative(String key) {
    final actual = getRequired<num>(key);
    actual.assertNegative();
    interactsWith(key);
    return this as AssertableJson;
  }
}
