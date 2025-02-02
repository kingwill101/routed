import 'package:routed_testing/src/assertable_json/assertable_json_base.dart';
import 'package:test/test.dart';
import 'assertable_json.dart';

/// A mixin that provides assertion methods for JSON data validation.
///
/// This mixin extends [AssertableJsonBase] to provide methods for validating JSON
/// structure and content. It includes methods for checking:
/// * Presence or absence of keys
/// * Count of elements
/// * Value existence
/// * Nested property validation
///
/// Example usage:
///
/// final json = AssertableJson({'key': 'value'});
/// json.has('key')
///     .count('items', 3)
///     .missing('nonexistent');
///
mixin HasMixin on AssertableJsonBase {
  /// Verifies the count of elements at a specific key or at the root level.
  ///
  /// If only [key] is provided, verifies the root level count.
  /// If [length] is provided, verifies the count at the specified [key].
  ///
  /// Returns this instance for method chaining.
  AssertableJson count(dynamic key, [int? length]) {
    if (length == null) {
      expect(this.length(), equals(key),
          reason: 'Root level does not have the expected size');
      return this as AssertableJson;
    }

    expect(this.length(key), equals(length),
        reason: 'Property [$key] does not have the expected size');
    interactsWith(key);
    return this as AssertableJson;
  }

  /// Verifies that the count of elements at [key] is between [min] and [max].
  ///
  /// Returns this instance for method chaining.
  AssertableJson countBetween(dynamic key, dynamic min, dynamic max) {
    final length = this.length(key);
    expect(length >= min && length <= max, isTrue,
        reason: 'Property [$key] size is not between $min and $max');
    interactsWith(key);
    return this as AssertableJson;
  }

  /// Verifies the existence of a [key] and optionally its content.
  ///
  /// Can be used in three ways:
  /// * `has(key)` - Verifies key exists
  /// * `has(key, count)` - Verifies key exists with specific count
  /// * `has(key, count, callback)` - Verifies key exists with count and executes callback
  ///
  /// Returns this instance for method chaining.
  AssertableJson has(dynamic key,
      [dynamic arg1, AssertableJsonCallback? arg2]) {
    expect(exists(key), isTrue, reason: 'Property [$key] does not exist');
    interactsWith(key);

    if (arg2 != null) {
      return has(key, (json) {
        if (arg1 != null) {
          count(key, arg1 as int);
        }
        return first(arg2).etc();
      });
    }

    if (arg1 is AssertableJsonCallback) {
      return scope(key, arg1);
    }

    if (arg1 != null) {
      return count(key, arg1 as int);
    }

    return this as AssertableJson;
  }

  /// Verifies the existence of a nested property at [path].
  ///
  /// Returns this instance for method chaining.
  AssertableJson hasNested(String path) {
    expect(exists(path), isTrue,
        reason: 'Expected JSON to have nested key $path');
    interactsWith(path);
    return this as AssertableJson;
  }

  /// Verifies the existence of all specified [keys].
  ///
  /// Accepts either a single String or a List<String>.
  /// Returns this instance for method chaining.
  AssertableJson hasAll(dynamic keys) {
    if (keys is String) {
      return has(keys);
    }

    if (keys is List<String>) {
      for (var key in keys) {
        has(key);
      }
    }
    return this as AssertableJson;
  }

  /// Verifies that all specified [values] exist in the JSON.
  ///
  /// Returns this instance for method chaining.
  AssertableJson hasValues(List<dynamic> values) {
    final allValues = this.values();
    for (var value in values) {
      expect(allValues.contains(value), isTrue,
          reason: 'Expected JSON to have value $value');
    }
    return this as AssertableJson;
  }

  /// Verifies that at least one of the specified [keys] exists.
  ///
  /// Accepts either a single String or a List<String>.
  /// Returns this instance for method chaining.
  AssertableJson hasAny(dynamic keys) {
    if (keys is String) {
      return has(keys);
    }

    if (keys is List<String>) {
      final hasAnyKey = keys.any((key) => exists(key));
      expect(hasAnyKey, isTrue,
          reason: 'None of properties [${keys.join(", ")}] exist');
    }
    return this as AssertableJson;
  }

  /// Verifies that all specified [keys] are missing from the JSON.
  ///
  /// Accepts either a single String or a List<String>.
  /// Returns this instance for method chaining.
  AssertableJson missingAll(dynamic keys) {
    if (keys is String) {
      return missing(keys);
    }

    if (keys is List<String>) {
      for (var key in keys) {
        missing(key);
      }
    }
    return this as AssertableJson;
  }

  /// Verifies that the specified [key] is missing from the JSON.
  ///
  /// Returns this instance for method chaining.
  AssertableJson missing(String key) {
    expect(exists(key), isFalse,
        reason:
            'Property [$key] was found while it was expected to be missing');
    return this as AssertableJson;
  }
}
