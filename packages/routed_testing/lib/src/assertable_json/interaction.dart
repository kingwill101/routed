import 'package:test/expect.dart';

import 'assertable_json.dart';

/// A mixin that tracks property access in JSON objects and provides verification
/// capabilities.
///
/// This mixin maintains a set of accessed property keys and offers methods to:
/// * Track which properties have been accessed
/// * Verify that all properties have been interacted with
/// * Mark all properties as accessed
///
/// Example usage:
///
/// class MyJson with InteractionMixin {
///   final Map`<String, dynamic> _json;
///
///   @override
///   dynamic get json => _json;
///
///   void validateAllPropertiesAccessed() {
///     verifyInteracted();
///   }
/// }
///
mixin InteractionMixin {
  final Set<String> _interacted = {};

  dynamic get json;

  /// Records an interaction with the specified JSON property [key].
  ///
  /// For non-List JSON objects, tracks the root property name when accessing
  /// nested properties using dot notation.
  void interactsWith(String key) {
    if (json is! List) {
      final prop = key.split('.').first;
      _interacted.add(prop);
    }
  }

  /// Verifies that all properties in the JSON object have been accessed.
  ///
  /// Throws a [TestFailure] if any properties have not been interacted with.
  /// Only applies to non-List JSON objects.
  void verifyInteracted() {
    if (json is! List) {
      final unInteractedKeys = json.keys.toSet().difference(_interacted);
      expect(unInteractedKeys.isEmpty, isTrue,
          reason: 'Unexpected properties were found: $unInteractedKeys');
    }
  }

  /// Marks all properties in the JSON object as accessed.
  ///
  /// Returns this instance as an [AssertableJson] for method chaining.
  /// Only applies to non-List JSON objects.
  AssertableJson etc() {
    if (json is! List) {
      _interacted.addAll(json.keys);
    }
    return this as AssertableJson;
  }
}
