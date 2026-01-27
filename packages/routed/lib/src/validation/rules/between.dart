library;

import 'package:routed/src/validation/abstract_rule.dart';

/// Validation rule that checks if a value is between a given range.
class BetweenRule extends AbstractValidationRule {
  @override
  String get name => 'between';
  @override
  String message(dynamic value, [List<String>? options]) {
    if (options != null && options.length == 2) {
      return 'The field must be between ${options[0]} and ${options[1]}.';
    }
    return 'The field must be between a given range.';
  }

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null || options == null || options.length != 2) return false;

    try {
      final min = num.tryParse(options[0]);
      final max = num.tryParse(options[1]);
      final inputValue = num.tryParse(value.toString());

      if (min == null || max == null || inputValue == null) return false;

      return inputValue >= min && inputValue <= max;
    } catch (e) {
      return false;
    }
  }
}
