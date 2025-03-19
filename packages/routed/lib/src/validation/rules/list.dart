import 'package:routed/src/validation/rule.dart';

class ListRule extends ValidationRule {
  @override
  String get name => 'list';

  @override
  String message(dynamic value, [List<String>? options]) =>
      'The field must be a list.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null || value is! List) return false;

    final listValue = value;
    for (int i = 0; i < listValue.length; i++) {
      if (!listValue.asMap().containsKey(i)) return false;
    }
    return true;
  }
}
