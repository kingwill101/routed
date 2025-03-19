import 'package:routed/src/validation/abstract_rule.dart';

class DoesntStartWithRule extends AbstractValidationRule {
  @override
  String get name => 'doesnt_start_with';
  @override
  String message(dynamic value, [List<String>? options]) =>
      'The field must not start with any of the following: ${options?.join(', ')}.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null || options == null) return false;
    final strValue = value.toString();
    for (final prefix in options) {
      if (strValue.startsWith(prefix)) return false;
    }
    return true;
  }
}
