import 'package:routed/src/validation/rule.dart';

/// A validation rule that checks if a given value is a valid string.
class StringRule implements ValidationRule {
  /// The name of the validation rule.
  @override
  String get name => 'string';

  /// The error message to be displayed if validation fails.
  @override
  String get message => 'This field must be a valid string.';

  /// Validates whether the provided [value] is a valid string.
  ///
  /// The [value] can be of any type, but it will be converted to a string
  /// for validation purposes. If the [value] is `null`, the validation
  /// will fail. The validation checks if the string does not contain
  /// any forward slashes (`/`).
  ///
  /// [options] is an optional parameter that can be used to pass additional
  /// options for validation, but it is not used in this rule.
  ///
  /// Returns `true` if the [value] is a valid string according to the rule,
  /// otherwise returns `false`.
  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null) return false;
    return RegExp(r'^[^/]+$').hasMatch(value.toString());
  }
}
