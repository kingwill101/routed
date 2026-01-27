library;

import 'package:routed/src/validation/abstract_rule.dart';

/// A validation rule that checks if a given value is a valid email address.
class EmailRule extends AbstractValidationRule {
  @override
  String get name => 'email';

  /// The error message to be displayed if the validation fails.
  @override
  String message(dynamic value, [List<String>? options]) =>
      'This field must be a valid email address.';

  /// Validates whether the provided [value] is a valid email address.
  ///
  /// The [value] parameter is the input to be validated. It should be of type [String].
  /// If the [value] is not a [String], the method returns `false`.
  ///
  /// The [options] parameter is an optional list of strings that can be used to
  /// provide additional options for validation. It is not used in this implementation.
  ///
  /// Returns `true` if the [value] matches the email pattern, otherwise `false`.
  @override
  bool validate(dynamic value, [List<String>? options]) {
    // Check if the value is a String
    if (value is! String) return false;

    // Regular expression pattern to validate email addresses
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');

    // Check if the value matches the email pattern
    return emailRegex.hasMatch(value);
  }
}
