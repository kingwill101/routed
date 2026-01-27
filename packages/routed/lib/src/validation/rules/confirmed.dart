library;

import 'package:routed/src/validation/context_aware_rule.dart';

/// Validation rule that checks if the value matches its confirmation field.
class ConfirmedRule extends ContextAwareValidationRule {
  @override
  String get name => 'confirmed';
  @override
  String message(dynamic value, [List<String>? options]) =>
      'The field confirmation does not match.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (options == null || options.isEmpty) return false;
    if (contextValues.isEmpty) return false;

    final confirmationFieldName = options[0];
    if (contextValues.containsKey(confirmationFieldName)) return false;

    final confirmationValue = contextValues[confirmationFieldName];

    return value == confirmationValue;
  }
}
