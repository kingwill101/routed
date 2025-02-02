import 'package:routed_testing/src/assertable_json/conditionable.dart';
import 'package:routed_testing/src/assertable_json/conditions.dart';
import 'package:routed_testing/src/assertable_json/dd.dart';
import 'package:routed_testing/src/assertable_json/has.dart';
import 'package:routed_testing/src/assertable_json/matching.dart';
import 'package:routed_testing/src/assertable_json/tappable.dart';

import 'assertable_json_base.dart';

/// A powerful JSON testing utility that provides fluent assertions for JSON structures.
///
/// The [AssertableJson] class combines multiple mixins to provide a rich set of
/// testing capabilities:
/// * [TappableMixin] for chaining operations
/// * [ConditionableMixin] for conditional assertions
/// * [ConditionMixin] for numeric validations
/// * [MatchingMixin] for pattern matching
/// * [HasMixin] for property verification
///
/// Core Features:
/// * Property existence checking
/// * Type validation
/// * Numeric comparisons
/// * Pattern matching
/// * Nested object navigation
/// * Array validation
///
/// Basic Usage:
/// ```dart
/// final json = AssertableJson({
///   'name': 'John',
///   'age': 30,
///   'scores': [85, 90, 95]
/// });
///
/// json
///   .has('name')
///   .whereType<String>('name')
///   .where('name', 'John')
///   .has('age')
///   .isGreaterThan('age', 25)
///   .count('scores', 3);
/// ```
///
/// Nested Objects:
/// ```dart
/// final json = AssertableJson({
///   'user': {
///     'profile': {
///       'email': 'john@example.com'
///     }
///   }
/// });
///
/// json.hasNested('user.profile.email');
/// ```
///
/// Conditional Testing:
/// ```dart
/// json.when(isAdmin, (json) {
///   json.has('adminPrivileges');
/// });
/// ```
///
/// Array Validation:
/// ```dart
/// json.has('items', 3, (items) {
///   items.each((item) {
///     item.has('id').has('name');
///   });
/// });
/// ```
///
/// Numeric Assertions:
/// ```dart
/// json
///   .isGreaterThan('age', 18)
///   .isLessThan('score', 100)
///   .isBetween('rating', 1, 5);
/// ```
///
/// Pattern Matching:
/// ```dart
/// json
///   .whereType<String>('email')
///   .whereContains('email', '@')
///   .whereIn('status', ['active', 'pending']);
/// ```
///
/// Schema Validation:
/// ```dart
/// json.matchesSchema({
///   'id': int,
///   'name': String,
///   'active': bool
/// });
/// ```
///
/// Property Interaction Tracking:
/// The class automatically tracks which properties have been accessed during
/// testing. Use [verifyInteracted] to ensure all properties have been checked:
/// ```dart
/// json
///   .has('name')
///   .has('age')
///   .verifyInteracted(); // Fails if any properties weren't checked
/// ```
///
/// See also:
/// * [AssertableJsonBase] for core functionality
/// * [HasMixin] for property verification methods
/// * [ConditionMixin] for numeric assertions
/// * [MatchingMixin] for pattern matching capabilities
class AssertableJson extends AssertableJsonBase
    with
        TappableMixin,
        ConditionableMixin,
        ConditionMixin,
        MatchingMixin,
        DebugMixin,
        HasMixin {
  @override
  dynamic json = {};

  /// Constructs an [AssertableJson] instance with the provided [jsonData].
  ///
  /// If [jsonData] is `null`, an empty JSON object `{}` will be used instead.
  /// Accepts either a JSON object `{}` or array `[]` as valid input.
  AssertableJson(dynamic jsonData) : json = jsonData ?? {};
}
