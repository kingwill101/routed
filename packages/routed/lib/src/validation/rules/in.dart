import 'package:routed/src/validation/rule.dart';

/// The `InRule` class is a validation rule that checks if a given value
/// is within a specified list of allowed values.
class InRule implements ValidationRule {
  /// The name of the validation rule.
  @override
  String get name => 'in';

  /// The error message returned when validation fails.
  @override
  String get message => 'This field must be one of the allowed values.';

  /// Validates whether the provided [value] is within the [options] list.
  ///
  /// The [value] parameter is the value to be validated.
  /// The [options] parameter is an optional list of allowed values.
  /// Returns `true` if [value] is in [options], otherwise `false`.
  @override
  bool validate(dynamic value, [List<String>? options]) {
    // If no options are provided, validation fails.
    if (options == null) return false;
    // Check if the value (converted to a string) is in the list of options.
    return options.contains(value.toString());
  }
}
