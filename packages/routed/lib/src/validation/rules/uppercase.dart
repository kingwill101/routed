import 'package:routed/src/validation/rule.dart';

class UppercaseRule extends ValidationRule {
  @override
  String get name => 'uppercase';

  @override
  String message(dynamic value, [List<String>? options]) =>
      'The field must be uppercase.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null) return false;
    return value.toString() == value.toString().toUpperCase();
  }
}
