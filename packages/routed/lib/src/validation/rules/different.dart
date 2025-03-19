/// Validation rule that checks if the value is different from another field.
library;

import 'package:routed/src/validation/context_aware_rule.dart';

class DifferentRule extends ContextAwareValidationRule {
  @override
  String get name => 'different';
  @override
  String message(dynamic value, [List<String>? options]) {
    if (options != null && options.isNotEmpty) {
      return 'The field must be different from ${options[0]}.';
    }
    return 'The field must be different from another field.';
  }

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (options == null || options.isEmpty) return false;
    if (contextValues == null) return false;

    final otherFieldName = options[0];
    if (!contextValues!.containsKey(otherFieldName)) return false;

    final otherValue = contextValues![otherFieldName];

    return value != otherValue;
  }
}
