/// A validation rule that checks if a given value is a valid date in the format YYYY-MM-DD.
library;

import 'package:routed/src/validation/abstract_rule.dart';

class DateRule extends AbstractValidationRule {
  @override
  String get name => "date";

  /// The error message to be displayed if the validation fails.
  @override
  String message(dynamic value, [List<String>? options]) =>
      'This field must be a valid date (YYYY-MM-DD).';

  /// Validates whether the provided [value] is a valid date in the format YYYY-MM-DD.
  ///
  /// The [value] parameter is the input to be validated. It can be of any type.
  /// The [options] parameter is an optional list of strings that can be used for additional validation options.
  ///
  /// Returns `true` if the [value] matches the date format YYYY-MM-DD, otherwise returns `false`.
  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null) return false; // Return false if the value is null.
    // Check if the value matches the regular expression for the date format YYYY-MM-DD.
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value.toString());
  }
}
