import 'package:routed/src/validation/rule.dart';

class LessThanOrEqualRule extends ValidationRule {
  @override
  String get name => 'less_than_or_equal';

  @override
  String message(dynamic value, [List<String>? options]) {
    if (options != null && options.isNotEmpty) {
      return 'The field must be less than or equal to ${options[0]}.';
    }
    return 'The field must be less than or equal to the specified value.';
  }

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null || options == null || options.isEmpty) return false;

    final otherValue = num.tryParse(options[0]);
    final thisValue = num.tryParse(value.toString());

    if (otherValue == null || thisValue == null) return false;

    return thisValue <= otherValue;
  }
}
