import 'package:routed/src/validation/rule.dart';

class LowercaseRule extends ValidationRule {
  @override
  String get name => 'lowercase';

  @override
  String message(dynamic value, [List<String>? options]) =>
      'The field must be lowercase.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null) return false;
    return value.toString() == value.toString().toLowerCase();
  }
}
