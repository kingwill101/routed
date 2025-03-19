import 'package:routed/src/validation/rule.dart';

/// A validation rule that checks if a given value is an array (List).
class ArrayRule extends ValidationRule {
  @override
  String get name => "array";

  @override
  String message(dynamic value, [List<String>? options]) {
    if (options != null && options.isNotEmpty) {
      return 'The array may only contain the following keys: ${options.join(", ")}.';
    }
    return 'This field must be an array.';
  }

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null || value is! List) return false;

    // If no specific keys are required, just validate it's an array
    if (options == null || options.isEmpty) return true;

    // If keys are specified, validate that the array contains only those values
    if (options.isNotEmpty) {
      final allowedValues = options.toSet();
      return value.every((item) => allowedValues.contains(item.toString()));
    }

    return true;
  }
}
