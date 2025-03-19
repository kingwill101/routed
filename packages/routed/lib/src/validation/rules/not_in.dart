import 'package:routed/src/validation/rule.dart';

class NotInRule extends ValidationRule {
  @override
  String get name => 'not_in';

  @override
  String message(dynamic value, [List<String>? options]) =>
      'The selected value is invalid.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null || options == null) return false;
    return !options.contains(value.toString());
  }
}
