/// Validation rule that checks if the value contains only alphabetic characters,
/// as well as dashes and underscores.
library;

import 'package:routed/src/validation/abstract_rule.dart';

class AlphaDashRule extends AbstractValidationRule {
  @override
  String get name => 'alpha_dash';
  @override
  String message(dynamic value, [List<String>? options]) =>
      'The field may only contain letters, numbers, dashes, and underscores.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null) return false;

    return RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(value.toString());
  }
}
