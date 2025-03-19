import 'package:routed/src/validation/rule.dart';

/// A validation rule that checks if the provided value does not exceed a specified maximum value.
///
/// If the value is a [String], its length must be less than or equal to the maximum value.
/// If the value is a [num], the value itself must be less than or equal to the maximum value.
class MaxRule extends ValidationRule {
  /// The name of the validation rule.
  @override
  String get name => 'max';

  /// The error message to be displayed if the validation fails.
  @override
  String message(dynamic value, [List<String>? options]) {
    if (options != null && options.isNotEmpty) {
      return 'This field must not exceed ${options[0]}.';
    }
    return 'This field must not exceed the maximum allowed value.';
  }

  /// Validates whether the provided [value] meets the maximum requirement.
  ///
  /// The [value] is expected to be a [String] or a [num]. The [options] parameter should contain
  /// a single element which is the maximum value as a [String] that can be parsed into a [num].
  ///
  /// For a [String] value, its length must be less than or equal to the specified maximum.
  /// For a [num] value, the number itself must be less than or equal to the specified maximum.
  ///
  /// Returns `true` if the [value] meets the maximum requirement, otherwise returns `false`.
  @override
  bool validate(dynamic value, [List<String>? options]) {
    // Check if options are provided and not empty
    if (options == null || options.isEmpty) return false;

    // Try to parse the first option as a number to get the maximum allowed value
    final max = num.tryParse(options[0]);
    if (max == null) return false;

    // Check if the value is a string and its length does not exceed the maximum value
    if (value is String) {
      return value.length <= max;
    }

    // Check if the value is a number and does not exceed the maximum value
    if (value is num) {
      return value <= max;
    }

    // Return false if the value is neither a string nor a number
    return false;
  }
}
