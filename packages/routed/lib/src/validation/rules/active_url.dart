import 'package:routed/src/validation/context_aware_rule.dart';

class ActiveUrlRule extends ContextAwareValidationRule {
  @override
  String get name => 'active_url';

  @override
  String message(dynamic value, [List<String>? options]) =>
      'The field must be a valid URL.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null) return false;

    // Basic URL format check
    return RegExp(
            r'^(https?://)?([\da-z\.-]+)\.([a-z\.]{2,6})([\/\w \.-]*)*\/?$')
        .hasMatch(value.toString());
  }
}
