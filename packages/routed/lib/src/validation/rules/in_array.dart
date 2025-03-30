import 'package:routed/src/validation/context_aware_rule.dart';

class InArrayRule extends ContextAwareValidationRule {
  @override
  String get name => 'in_array';

  @override
  String message(dynamic value, [List<String>? options]) =>
      'The selected value is invalid.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null || options == null || options.isEmpty) return false;
    if (contextValues.isEmpty) return false;

    final otherFieldName = options[0];
    if (!contextValues.containsKey(otherFieldName)) return false;

    final otherValue = contextValues[otherFieldName];

    if (otherValue is! List) return false;

    return otherValue.contains(value);
  }
}
