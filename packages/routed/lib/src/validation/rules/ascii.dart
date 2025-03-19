import 'package:routed/src/validation/abstract_rule.dart';

class AsciiRule extends AbstractValidationRule {
  @override
  String get name => 'ascii';
  @override
  String message(dynamic value, [List<String>? options]) =>
      'The field must contain only ASCII characters.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null) return false;
    return RegExp(r'^[\x00-\x7F]+$').hasMatch(value.toString());
  }
}
