import 'package:routed/src/validation/context_aware_rule.dart';
import 'package:routed/src/validation/rule.dart';

/// Validation rule that checks if a date is after a given date.
class AfterRule extends ContextAwareValidationRule {
  @override
  String get name => 'after';
  @override
  String message(dynamic value, [List<String>? options]) {
    if (options != null && options.isNotEmpty) {
      return 'The field must be a date after ${options[0]}.';
    }
    return 'The field must be a date after a given date.';
  }

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null || options == null || options.isEmpty) return false;

    try {
      final inputValue = DateTime.tryParse(value.toString());
      final afterDate = DateTime.tryParse(options[0]);

      if (inputValue == null || afterDate == null) return false;

      return inputValue.isAfter(afterDate);
    } catch (e) {
      return false;
    }
  }
}
