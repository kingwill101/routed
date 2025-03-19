import 'package:routed/src/validation/rule.dart';

class AfterOrEqualRule extends ValidationRule {
  @override
  String get name => 'after_or_equal';

  @override
  String message(dynamic value, [List<String>? options]) {
    if (options != null && options.isNotEmpty) {
      return 'The field must be a date after or equal to ${options[0]}.';
    }
    return 'The field must be a date after or equal to the specified date.';
  }

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null || options == null || options.isEmpty) return false;

    final compareDate = DateTime.tryParse(options[0]);
    final thisDate = DateTime.tryParse(value.toString());

    if (compareDate == null || thisDate == null) return false;

    return thisDate.isAtSameMomentAs(compareDate) ||
        thisDate.isAfter(compareDate);
  }
}
