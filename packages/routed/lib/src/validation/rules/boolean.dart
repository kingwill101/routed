library;

import 'package:routed/src/validation/abstract_rule.dart';

/// Validation rule that checks if the value is a boolean.
class BooleanRule extends AbstractValidationRule {
  @override
  String get name => 'boolean';
  @override
  String message(dynamic value, [List<String>? options]) =>
      'The field must be a boolean.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null) return false;

    return value is bool ||
        value == 'true' ||
        value == 'false' ||
        value == 1 ||
        value == 0 ||
        value == '1' ||
        value == '0';
  }
}
