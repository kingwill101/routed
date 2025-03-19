import 'package:routed/src/validation/abstract_rule.dart';

class DistinctRule extends AbstractValidationRule {
  @override
  String get name => 'distinct';
  @override
  String message(dynamic value, [List<String>? options]) =>
      'The field must not have any duplicate values.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null || value is! List) return false;

    final listValue = value;
    final seen = <dynamic>{};
    for (final item in listValue) {
      if (seen.contains(item)) return false;
      seen.add(item);
    }
    return true;
  }
}
