import 'package:routed/src/validation/context_aware_rule.dart';

class SameRule extends ContextAwareValidationRule {
  @override
  String get name => 'same';

  @override
  String message(dynamic value, [List<String>? options]) =>
      'The field must be the same as ${options?.first}.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (options == null || options.isEmpty) return false;
    if (contextValues.isEmpty) return false;

    final otherFieldName = options[0];
    if (!contextValues.containsKey(otherFieldName)) return false;

    final otherValue = contextValues[otherFieldName];

    return value == otherValue;
  }
}
