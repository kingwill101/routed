import 'package:routed/src/validation/rule.dart';

/// A validation rule that checks if the length of a given string does not exceed a specified maximum length.
class MaxLengthRule implements ValidationRule {
  /// The name of the validation rule.
  @override
  String get name => 'max_length';

  /// The error message to be displayed if the validation fails.
  @override
  String get message => 'This field must not exceed the maximum length.';

  /// Validates whether the provided [value] meets the maximum length requirement.
  ///
  /// The [value] is expected to be a [String]. The [options] parameter should contain
  /// a single element which is the maximum length as a [String] that can be parsed into an [int].
  ///
  /// Returns `true` if the [value] is a [String] and its length is less than or equal to the specified maximum length.
  /// Returns `false` if the [options] parameter is `null` or empty, if the maximum length cannot be parsed,
  /// or if the [value] is not a [String].
  @override
  bool validate(dynamic value, [List<String>? options]) {
    // Check if options are provided and not empty
    if (options == null || options.isEmpty) return false;

    // Try to parse the first option as an integer to get the maximum length
    final maxLength = int.tryParse(options[0]);
    if (maxLength == null) return false;

    // Check if the value is a string and its length does not exceed the maximum length
    if (value is String) {
      return value.length <= maxLength;
    }

    // Return false if the value is not a string
    return false;
  }
}
