import 'package:routed_validation/src/validation/rule.dart';

/// Validates that a value starts with at least one supplied option.
class StartsWithRule extends ValidationRule {
  @override
  String get name => 'starts_with';

  @override
  String message(dynamic value, [List<String>? options]) =>
      'The field must start with one of the following: ${options?.join(', ')}.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null || options == null) return false;
    final strValue = value.toString();
    for (final prefix in options) {
      if (strValue.startsWith(prefix)) return true;
    }
    return false;
  }
}
