/// Validation rule that checks if the value has an exact number of digits.
library;

import 'package:routed/src/validation/abstract_rule.dart';

class DigitsRule extends AbstractValidationRule {
  @override
  String get name => 'digits';
  @override
  String message(dynamic value, [List<String>? options]) {
    if (options != null && options.isNotEmpty) {
      return 'The field must be ${options[0]} digits.';
    }
    return 'The field must have an exact number of digits.';
  }

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null || options == null || options.isEmpty) return false;

    final length = int.tryParse(options[0]);
    if (length == null) return false;

    return value.toString().length == length &&
        RegExp(r'^\d+$').hasMatch(value.toString());
  }
}
