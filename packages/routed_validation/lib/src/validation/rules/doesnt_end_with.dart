import 'package:routed_validation/src/validation/abstract_rule.dart';

/// Validates that a value does not end with any supplied option.
class DoesntEndWithRule extends AbstractValidationRule {
  @override
  String get name => 'doesnt_end_with';
  @override
  String message(dynamic value, [List<String>? options]) =>
      'The field must not end with any of the following: ${options?.join(', ')}.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null || options == null) return false;
    final strValue = value.toString();
    for (final suffix in options) {
      if (strValue.endsWith(suffix)) return false;
    }
    return true;
  }
}
