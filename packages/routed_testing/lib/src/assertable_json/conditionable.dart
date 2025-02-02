import 'package:routed_testing/src/assertable_json/assertable_json.dart';

/// A mixin that provides conditional assertion methods for JSON testing.
///
/// This mixin adds methods that allow conditional execution of assertions based on
/// boolean conditions. It enables more flexible and dynamic testing scenarios by
/// allowing assertions to be executed only when specific conditions are met.
mixin ConditionableMixin {
  /// Executes the [callback] on this [AssertableJson] instance when the [condition] is true.
  ///
  /// Returns this instance to allow method chaining.
  ///
  ///
  /// json.when(isAdmin, (json) {
  ///   json.has('adminField');
  /// });
  ///
  AssertableJson when(bool condition, Function(AssertableJson) callback) {
    if (condition) {
      callback(this as AssertableJson);
    }
    return this as AssertableJson;
  }

  /// Executes the [callback] on this [AssertableJson] instance when the [condition] is false.
  ///
  /// Returns this instance to allow method chaining.
  ///
  ///
  /// json.unless(isAdmin, (json) {
  ///   json.hasNot('adminField');
  /// });
  ///
  AssertableJson unless(bool condition, Function(AssertableJson) callback) {
    if (!condition) {
      callback(this as AssertableJson);
    }
    return this as AssertableJson;
  }
}
