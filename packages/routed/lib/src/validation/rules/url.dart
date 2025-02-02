import 'package:routed/src/validation/rule.dart';

/// A validation rule that checks if a given value is a valid URL.
class UrlRule implements ValidationRule {
  /// The name of the validation rule.
  @override
  String get name => 'url';

  /// The error message returned when the validation fails.
  @override
  String get message => 'This field must be a valid URL.';

  /// Validates whether the provided [value] is a valid URL.
  ///
  /// The [value] parameter is the input that needs to be validated.
  /// The optional [options] parameter can be used to pass additional
  /// options for validation, but it is not used in this implementation.
  ///
  /// Returns `true` if the [value] is a valid URL, otherwise `false`.
  @override
  bool validate(dynamic value, [List<String>? options]) {
    // If the value is null, it is not a valid URL.
    if (value == null) return false;

    // Regular expression to match a valid URL.
    // The URL must start with http:// or https:// and followed by valid characters.
    return RegExp(r'^https?://[^\s/$.?#].[^\s]*$').hasMatch(value.toString());
  }
}
