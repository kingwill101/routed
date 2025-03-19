import 'package:routed/src/validation/abstract_rule.dart';

class ContainsRule extends AbstractValidationRule {
  @override
  String get name => 'contains';
  @override
  String message(dynamic value, [List<String>? options]) {
    if (options != null && options.isNotEmpty) {
      return 'The field must contain all of the following values: ${options.join(', ')}.';
    }
    return 'The field must contain the specified values.';
  }

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null || options == null || options.isEmpty || value is! List) {
      return false;
    }

    final listValue = value;
    for (final item in options) {
      if (!listValue.contains(item)) return false;
    }
    return true;
  }
}
