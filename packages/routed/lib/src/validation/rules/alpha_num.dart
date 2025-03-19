/// Validation rule that checks if the value contains only alphabetic and numeric characters.
library;

import 'package:routed/src/validation/abstract_rule.dart';

class AlphaNumRule extends AbstractValidationRule {
  @override
  String get name => 'alpha_num';
  @override
  String message(dynamic value, [List<String>? options]) =>
      'The field must contain only letters and numbers.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null) return false;

    return RegExp(r'^[a-zA-Z0-9]+$').hasMatch(value.toString());
  }
}
