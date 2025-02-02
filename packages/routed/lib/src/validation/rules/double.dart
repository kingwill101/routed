import 'package:routed/src/validation/rule.dart';

/// A validation rule that checks if a given value is a valid double.
class DoubleRule implements ValidationRule {
  /// The name of the validation rule.
  @override
  String get name => 'double';

  /// The error message returned when the validation fails.
  @override
  String get message => 'This field must be a valid double.';

  /// Validates whether the provided [value] is a valid double.
  ///
  /// The [value] can be of any type, but it will be converted to a string
  /// for the validation check. The optional [options] parameter is not used
  /// in this validation rule.
  ///
  /// Returns `true` if the [value] is a valid double, otherwise `false`.
  @override
  bool validate(dynamic value, [List<String>? options]) {
    // If the value is null, it is not a valid double.
    if (value == null) return false;

    // Use a regular expression to check if the value is a valid double.
    return RegExp(r'^\d+(\.\d+)?$').hasMatch(value.toString());
  }
}
