import 'package:routed/src/validation/rule.dart';

/// A validation rule that ensures a given value meets a specified minimum value.
///
/// If the value is a [String], its length must be greater than or equal to the minimum value.
/// If the value is a [num], the value itself must be greater than or equal to the minimum value.
class MinRule extends ValidationRule {
  /// The name of the validation rule.
  @override
  String get name => 'min';

  /// The error message to be displayed if the validation fails.
  @override
  String message(dynamic value, [List<String>? options]) {
    if (options != null && options.isNotEmpty) {
      return 'This field must be at least ${options[0]}.';
    }
    return 'This field must be at least the minimum value.';
  }

  /// Validates whether the provided [value] meets the minimum requirement.
  ///
  /// The [value] is expected to be a [String] or a [num]. The [options] parameter should contain
  /// a single element which is the minimum value as a [String] that can be parsed into an [int].
  ///
  /// For a [String] value, its length must be greater than or equal to the specified minimum.
  /// For a [num] value, the number itself must be greater than or equal to the specified minimum.
  ///
  /// Returns `true` if the [value] meets the minimum requirement, otherwise returns `false`.
  @override
  bool validate(dynamic value, [List<String>? options]) {
    // Check if options are provided and not empty
    if (options == null || options.isEmpty) return false;

    // Try to parse the first option as a number to get the minimum allowed value
    final min = num.tryParse(options[0]);
    if (min == null) return false;

    // Check if the value is a string and its length is greater than or equal to the minimum value
    if (value is String) {
      return value.length >= min;
    }

    // Check if the value is a number and is greater than or equal to the minimum value
    if (value is num) {
      return value >= min;
    }

    // Return false if the value is neither a string nor a number
    return false;
  }
}
