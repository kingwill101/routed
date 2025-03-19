/// Validation rule that checks if the value has a number of digits within a range.
library;

import 'package:routed/src/validation/abstract_rule.dart';

class DigitsBetweenRule extends AbstractValidationRule {
  @override
  String get name => 'digits_between';
  @override
  String message(dynamic value, [List<String>? options]) {
    if (options != null && options.length == 2) {
      return 'The field must be between ${options[0]} and ${options[1]} digits.';
    }
    return 'The field must have a number of digits within a range.';
  }

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null || options == null || options.length != 2) return false;

    final min = int.tryParse(options[0]);
    final max = int.tryParse(options[1]);

    if (min == null || max == null) return false;

    final length = value.toString().length;

    return length >= min &&
        length <= max &&
        RegExp(r'^\d+$').hasMatch(value.toString());
  }
}
