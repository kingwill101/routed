import 'package:routed/src/validation/rule.dart';

/// A validation rule that checks if a given value is numeric.
class NumericRule extends ValidationRule {
  /// The name of the validation rule.
  @override
  String get name => 'numeric';

  /// The error message to be displayed if validation fails.
  @override
  String message(dynamic value, [List<String>? options]) =>
      'This field must be a number.';

  /// Validates whether the provided [value] is numeric.
  ///
  /// This method attempts to parse the [value] as a number. If the parsing
  /// is successful, the method returns `true`, indicating that the value
  /// is numeric. If the parsing fails or if the [value] is `null`, the
  /// method returns `false`.
  ///
  /// The [options] parameter is not used in this validation rule, but it
  /// is included to adhere to the [ValidationRule] interface.
  ///
  /// - [value]: The value to be validated.
  /// - [options]: Additional options for validation (not used).
  ///
  /// Returns `true` if the [value] is numeric, otherwise `false`.
  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null) return false;
    return num.tryParse(value.toString()) != null;
  }
}
