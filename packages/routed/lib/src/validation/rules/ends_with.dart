import 'package:routed/src/validation/abstract_rule.dart';

class EndsWithRule extends AbstractValidationRule {
  @override
  String get name => 'ends_with';
  @override
  String message(dynamic value, [List<String>? options]) =>
      'The field must end with one of the following: ${options?.join(', ')}.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null || options == null) return false;
    final strValue = value.toString();
    for (final suffix in options) {
      if (strValue.endsWith(suffix)) return true;
    }
    return false;
  }
}
