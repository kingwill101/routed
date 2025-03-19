import 'package:routed/src/validation/rule.dart';

class GreaterThanRule extends ValidationRule {
  @override
  String get name => 'greater_than';

  @override
  String message(dynamic value, [List<String>? options]) {
    if (options != null && options.isNotEmpty) {
      return 'The field must be greater than ${options[0]}.';
    }
    return 'The field must be greater than the specified value.';
  }

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null || options == null || options.isEmpty) return false;

    final otherValue = num.tryParse(options[0]);
    final thisValue = num.tryParse(value.toString());

    if (otherValue == null || thisValue == null) return false;

    return thisValue > otherValue;
  }
}
