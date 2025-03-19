import 'package:routed/src/validation/rule.dart';

/// A validation rule that checks if the length of a given string
/// meets a specified minimum length.
class MinLengthRule extends ValidationRule {
  /// The name of the validation rule.
  @override
  String get name => 'minLength';

  /// The error message to be displayed if the validation fails.
  @override
  String message(dynamic value, [List<String>? options]) {
    if (options != null && options.isNotEmpty) {
      return 'This field must be at least ${options[0]} characters.';
    }
    return 'This field must be at least the minimum length.';
  }

  /// Validates whether the provided [value] meets the minimum length
  /// specified in [options].
  ///
  /// The [value] parameter is expected to be a [String]. The [options]
  /// parameter should contain at least one element, which is the minimum
  /// length as a [String] that can be parsed into an [int].
  ///
  /// Returns `true` if the [value] meets or exceeds the minimum length,
  /// otherwise returns `false`.
  @override
  bool validate(dynamic value, [List<String>? options]) {
    // Check if options are provided and not empty.
    if (options == null || options.isEmpty) return false;

    // Parse the first option as the minimum length.
    final minLength = int.tryParse(options[0]);
    if (minLength == null) return false;

    // Check if the value is a string and meets the minimum length.
    if (value is String) {
      return value.length >= minLength;
    }

    // Return false if the value is not a string.
    return false;
  }
}
