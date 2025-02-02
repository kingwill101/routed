import 'dart:convert';

import 'package:test/expect.dart';

/// A utility class for asserting JSON data in tests.
///
/// This class provides methods to validate JSON data structure, content,
/// and perform various assertions on JSON strings or objects.
///
/// Example usage:
///
/// final json = AssertableJsonString('{"name": "test", "value": 123}');
/// json
///   .assertCount(2)
///   .assertFragment({'name': 'test'});
///
class AssertableJsonString {
  /// The original JSON input, which can be either a string or a Map.
  final dynamic json;

  /// The decoded JSON data as a Map.
  final Map<String, dynamic> decoded;

  /// Creates a new [AssertableJsonString] instance.
  ///
  /// The [jsonable] parameter can be either a JSON string or a Map.
  /// Throws [ArgumentError] if the input is not valid JSON.
  AssertableJsonString(dynamic jsonable)
      : json = jsonable,
        decoded = _decodeJson(jsonable);

  /// Decodes the JSON input into a Map.
  ///
  /// Returns the input directly if it's already a Map, otherwise attempts to parse
  /// the string as JSON.
  /// Throws [ArgumentError] if the input cannot be decoded.
  static Map<String, dynamic> _decodeJson(dynamic jsonable) {
    if (jsonable is Map<String, dynamic>) {
      return jsonable;
    } else if (jsonable is String) {
      return jsonDecode(jsonable);
    }
    throw ArgumentError('Invalid JSON input');
  }

  /// Retrieves a value from the JSON using dot notation path.
  ///
  /// If [key] is null, returns the entire decoded JSON.
  /// Returns null if the path doesn't exist.
  dynamic jsonPath([String? key]) {
    if (key == null) return decoded;
    return _resolvePath(decoded, key);
  }

  /// Asserts that a JSON object or array has the expected number of elements.
  ///
  /// If [key] is provided, checks the count at that path.
  /// Returns this instance for method chaining.
  AssertableJsonString assertCount(int count, [String? key]) {
    final target = key != null ? jsonPath(key) : decoded;
    expect(target.length, equals(count),
        reason:
            'Failed to assert that the response count matched the expected $count');
    return this;
  }

  /// Asserts that the JSON matches exactly with the provided data.
  ///
  /// Compares the JSON after sorting keys to ensure consistent ordering.
  /// Returns this instance for method chaining.
  AssertableJsonString assertExact(Map<String, dynamic> data) {
    expect(
      jsonEncode(_sortKeys(decoded)),
      equals(jsonEncode(_sortKeys(data))),
      reason: 'JSON does not match exactly',
    );
    return this;
  }

  /// Asserts that the JSON contains all the key-value pairs in the provided data.
  ///
  /// The JSON may contain additional fields not present in the fragment.
  /// Returns this instance for method chaining.
  AssertableJsonString assertFragment(Map<String, dynamic> data) {
    final actual = jsonEncode(_sortKeys(decoded));
    for (var entry in _sortKeys(data).entries) {
      final fragment = jsonEncode({entry.key: entry.value});
      expect(
          actual.contains(fragment.substring(1, fragment.length - 1)), isTrue,
          reason: 'Unable to find JSON fragment: $fragment');
    }
    return this;
  }

  /// Asserts that the JSON matches the expected structure.
  ///
  /// If [structure] is null, performs an exact match.
  /// If [responseData] is provided, creates a new assertion on that data.
  /// Returns this instance for method chaining.
  /// Asserts that the JSON matches the expected structure.
  ///
  /// If [structure] is null, performs an exact match.
  /// If [responseData] is provided, creates a new assertion on that data.
  /// Returns this instance for method chaining.
  AssertableJsonString assertStructure(Map<String, dynamic>? structure,
      [dynamic responseData]) {
    if (structure == null) {
      return assertExact(decoded);
    }

    if (responseData != null) {
      return AssertableJsonString(responseData).assertStructure(structure);
    }
    _assertStructureRecursive(decoded, structure);
    return this;
  }

  /// Recursively validates the structure of the JSON against expected schema.
  void _assertStructureRecursive(dynamic actual, dynamic expected,
      [String path = '']) {
    if (expected is Map) {
      // Handle wildcard for arrays
      if (expected.containsKey('*')) {
        if (actual is! List) {
          fail(
              'Expected an array but got ${actual.runtimeType} at path: $path');
        }

        final wildcardStructure = expected['*'];
        for (var i = 0; i < actual.length; i++) {
          _assertStructureRecursive(actual[i], wildcardStructure, '$path[$i]');
        }
      } else {
        if (actual is! Map) {
          fail('Expected a map but got ${actual.runtimeType} at path: $path');
        }
        // Handle regular map structure
        for (var key in expected.keys) {
          expect(actual.containsKey(key), isTrue,
              reason: 'Expected key "$key" not found in JSON at path: $path');

          _assertStructureRecursive(
              actual[key], expected[key], path.isEmpty ? key : '$path.$key');
        }
      }
    } else if (expected is List) {
      if (actual is Map) {
        for (var i = 0; i < expected.length; i++) {
          final item = expected[i];
          if (item is String) {
            expect(actual.containsKey(item), isTrue,
                reason:
                    'Expected key "$item" not found in JSON at path: $path');
          } else {
            _assertStructureRecursive(actual, item, '$path[$i]');
          }
        }
      } else if (actual is List) {
        if (actual.length < expected.length) {
          fail(
              'List length mismatch at path: $path. Expected ${expected.length} items but got ${actual.length}');
        }
        for (var i = 0; i < expected.length; i++) {
          _assertStructureRecursive(actual[i], expected[i], '$path[$i]');
        }
      } else {
        fail('Expected a list but got ${actual.runtimeType} at path: $path');
      }
    } else {
      // Handle primitive values
      expect(actual, isNotNull,
          reason: 'Expected value not found in JSON at path: $path');
      if (expected != null && expected != '*') {
        expect(actual.runtimeType, expected.runtimeType,
            reason:
                'Type mismatch at path: $path. Expected ${expected.runtimeType} but got ${actual.runtimeType}');
      }
    }
  }

  /// Creates a new map with sorted keys for consistent comparison.
  Map<String, dynamic> _sortKeys(Map<String, dynamic> map) {
    final sorted = Map<String, dynamic>.from(map);
    sorted.forEach((key, value) {
      if (value is Map) {
        sorted[key] = _sortKeys(Map<String, dynamic>.from(value));
      }
    });
    return Map.fromEntries(
        sorted.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  /// Resolves a dot-notation path to its value in the JSON.
  dynamic _resolvePath(dynamic target, String path) {
    final parts = path.split('.');
    for (final part in parts) {
      if (target is! Map) return null;
      target = target[part];
    }
    return target;
  }
}
