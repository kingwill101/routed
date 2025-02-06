import 'package:routed_testing/src/assertable_json/assertable_json.dart';
import 'package:test/test.dart';

import 'assertable_json_base.dart';

/// A mixin that provides JSON assertion capabilities for testing.
///
/// This mixin extends [AssertableJsonBase] to provide methods for validating JSON data
/// structures. It includes functionality for:
/// * Comparing JSON property values against expected values
/// * Type checking of JSON properties
/// * Validating JSON schema structures
/// * Checking for presence/absence of values in arrays
/// * Ensuring consistent property ordering for reliable comparisons
///
/// Example usage:
///
/// final json = AssertableJson({'name': 'John', 'age': 30});
/// json.where('name', 'John')
///     .whereType<int>('age')
///     .whereIn('age', [25, 30, 35]);
///
mixin MatchingMixin on AssertableJsonBase {
  /// Ensures all nested maps within the given [value] have their entries sorted by key.
  ///
  /// This is used internally to provide consistent ordering when comparing maps.
  void ensureSorted(Map<String, dynamic> value) {
    value.forEach((key, val) {
      if (val is Map) {
        ensureSorted(val as Map<String, dynamic>);
      }
    });

    final sorted = Map.fromEntries(
        value.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
    value.clear();
    value.addAll(sorted);
  }

  /// Asserts that a property matches an expected value or satisfies a condition.
  ///
  /// The [key] specifies the property to check, and [expected] can be either:
  /// * A direct value to compare against
  /// * A function that returns true if the value is valid
  AssertableJson where(String key, dynamic expected) {
    (this as AssertableJson).has(key);
    final actual = get(key);

    if (expected is Function) {
      expect(expected(actual), isTrue,
          reason: 'Property [$key] was marked as invalid using a closure');
      return (this as AssertableJson);
    }

    if (expected is Map) {
      ensureSorted(expected as Map<String, dynamic>);
    }
    if (actual is Map) {
      ensureSorted(actual as Map<String, dynamic>);
    }

    expect(actual, equals(expected),
        reason: 'Property [$key] does not match expected value');

    return (this as AssertableJson);
  }

  /// Asserts that a property does not match an unexpected value.
  ///
  /// The [key] specifies the property to check, and [unexpected] can be either:
  /// * A direct value that should not match
  /// * A function that returns false if the value is valid
  AssertableJson whereNot(String key, dynamic unexpected) {
    final actual = getRequired(key);
    if (unexpected is Function) {
      expect(unexpected(actual), isFalse,
          reason: 'Property [$key] was marked as invalid using a closure');
    } else {
      expect(actual, isNot(equals(unexpected)),
          reason:
              'Property [$key] contains value that should be missing: $unexpected');
    }
    interactsWith(key);
    return this as AssertableJson;
  }

  /// Asserts that multiple properties match their expected values.
  ///
  /// The [bindings] map contains key-value pairs where each key is a property
  /// name and each value is the expected value for that property.
  AssertableJson whereAll(Map<String, dynamic> bindings) {
    bindings.forEach((key, value) => where(key, value));
    return this as AssertableJson;
  }

  /// Asserts that a property is of a specific type [T].
  ///
  /// The [key] specifies the property to check for type [T].
  AssertableJson whereType<T>(String key) {
    final actual = getRequired(key);
    expect(actual, isA<T>(),
        reason: 'Property [$key] is not of expected type [${T.toString()}]');
    interactsWith(key);
    return this as AssertableJson;
  }

  /// Asserts that multiple properties are all of type [T].
  ///
  /// The [keys] list specifies the properties to check.
  AssertableJson whereAllType<T>(List<String> keys) {
    for (var key in keys) {
      whereType<T>(key);
    }
    return this as AssertableJson;
  }

  /// Asserts that a property contains an expected value.
  ///
  /// For array properties, checks if [expected] is an element of the array.
  /// For string properties, checks if [expected] is a substring.
  AssertableJson whereContains(String key, dynamic expected) {
    final actual = getRequired(key);
    if (actual is List) {
      expect(actual.contains(expected), isTrue,
          reason: 'Property [$key] does not contain [$expected]');
    } else {
      expect(actual.toString().contains(expected.toString()), isTrue,
          reason: 'Property [$key] does not contain [$expected]');
    }
    interactsWith(key);
    return this as AssertableJson;
  }

  /// Asserts that a property's value is one of the provided [values].
  AssertableJson whereIn(String key, List<dynamic> values) {
    final actual = getRequired(key);
    expect(values.contains(actual), isTrue,
        reason: 'Expected $key to be one of $values');
    interactsWith(key);
    return this as AssertableJson;
  }

  /// Asserts that a property's value is not one of the provided [values].
  AssertableJson whereNotIn(String key, List<dynamic> values) {
    final actual = getRequired(key);
    expect(values.contains(actual), isFalse,
        reason: 'Expected $key to not be one of $values');
    interactsWith(key);
    return this as AssertableJson;
  }

  /// Validates that the JSON structure matches a given [schema].
  ///
  /// The [schema] map specifies property names and their expected types.
  /// Property names ending with '?' indicate optional fields.
  ///
  /// Example:
  /// ```dart
  /// json.matchesSchema({
  ///   'name': String,    // Required field
  ///   'age?': int,       // Optional field
  /// });
  /// ```
  AssertableJson matchesSchema(Map<String, Type> schema) {
    schema.forEach((key, type) {
      final isOptional = key.endsWith('?');
      final actualKey = isOptional ? key.substring(0, key.length - 1) : key;

      try {
        (this as AssertableJson).has(actualKey);
        final value = get(actualKey);
        expect(value.runtimeType, equals(type),
            reason:
                'Expected $actualKey to be of type $type but was ${value.runtimeType}');
        interactsWith(actualKey);
      } catch (e) {
        if (!isOptional) {
          fail('Required field $actualKey is missing');
        }
      }
    });
    return this as AssertableJson;
  }
}
