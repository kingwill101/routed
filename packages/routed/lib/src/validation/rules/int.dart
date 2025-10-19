import 'package:routed/src/validation/rule.dart';

/// A validation rule that checks if a given value is an integer.
class IntRule extends ValidationRule {
  /// The name of the validation rule.
  @override
  String get name => 'int';

  /// The error message returned when the validation fails.
  @override
  String message(dynamic value, [List<String>? options]) =>
      'This field must be an integer.';

  /// Validates whether the provided [value] is an integer.
  ///
  /// The [value] parameter is the value to be validated. It can be of any type.
  /// The optional [options] parameter is not used in this validation rule.
  ///
  /// Returns `true` if the [value] is a non-null integer, otherwise returns `false`.
  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null) return false; // Return false if the value is null.
    return RegExp(r'^\d+$').hasMatch(
      value.toString(),
    ); // Check if the value matches the integer pattern.
  }
}
