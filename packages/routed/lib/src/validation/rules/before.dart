/// Validation rule that checks if a date is before a given date.
library;

import 'package:routed/src/validation/abstract_rule.dart';

class BeforeRule extends AbstractValidationRule {
  @override
  String get name => 'before';
  @override
  String message(dynamic value, [List<String>? options]) {
    if (options != null && options.isNotEmpty) {
      return 'The field must be a date before ${options[0]}.';
    }
    return 'The field must be a date before a given date.';
  }

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null || options == null || options.isEmpty) return false;

    try {
      final inputValue = DateTime.tryParse(value.toString());
      final beforeDate = DateTime.tryParse(options[0]);

      if (inputValue == null || beforeDate == null) return false;

      return inputValue.isBefore(beforeDate);
    } catch (e) {
      return false;
    }
  }
}
