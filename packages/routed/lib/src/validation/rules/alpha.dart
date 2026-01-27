library;

import 'package:routed/src/validation/abstract_rule.dart';

/// Validation rule that checks if the value contains only alphabetic characters.
class AlphaRule extends AbstractValidationRule {
  @override
  String get name => 'alpha';
  @override
  String message(dynamic value, [List<String>? options]) =>
      'The field must contain only letters.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null) return false;

    return RegExp(r'^[a-zA-Z]+$').hasMatch(value.toString());
  }
}
