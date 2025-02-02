import 'package:routed/src/validation/rule.dart';

/// A validation rule that checks if a given value is an array (List).
class ArrayRule implements ValidationRule {
  /// The error message returned when the validation fails.
  @override
  String get message => 'This field must be an array.';

  /// Validates whether the provided [value] is an array (List).
  ///
  /// If [options] are provided, they are used to further validate the length
  /// of the array. The first element in [options] is treated as the minimum
  /// length, and the second element (if present) is treated as the maximum length.
  ///
  /// Returns `true` if the [value] is a valid array and meets the optional length
  /// constraints, otherwise returns `false`.
  ///
  /// - [value]: The value to be validated.
  /// - [options]: An optional list of strings where the first element is the minimum
  ///   length and the second element is the maximum length.
  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null) return false;

    // Check if the value is a list
    if (value is! List) return false;

    // Optional: Validate the length of the array if options are provided
    if (options != null && options.isNotEmpty) {
      final minLength = int.tryParse(options[0]);
      final maxLength = options.length > 1 ? int.tryParse(options[1]) : null;

      if (minLength != null && value.length < minLength) return false;
      if (maxLength != null && value.length > maxLength) return false;
    }

    return true;
  }

  /// The name of the validation rule.
  @override
  String get name => "array";
}
