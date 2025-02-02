import 'package:routed/src/validation/rule.dart';

/// A validation rule that checks if a value is present and not empty.
/// This rule is used to ensure that a field is not left blank.
class RequiredRule implements ValidationRule {
  /// The name of the validation rule.
  /// This is used to identify the rule in validation logic.
  @override
  String get name => 'required';

  /// The message that will be displayed if the validation fails.
  /// This provides feedback to the user indicating that the field is required.
  @override
  String get message => 'This field is required.';

  /// Validates the given value to check if it is not null and not empty.
  ///
  /// [value] - The value to be validated. It can be of any type.
  /// [options] - An optional list of strings that can be used for additional validation logic.
  ///
  /// Returns `true` if the value is not null and not empty, otherwise `false`.
  @override
  bool validate(dynamic value, [List<String>? options]) {
    return value != null && value.toString().isNotEmpty;
  }
}
