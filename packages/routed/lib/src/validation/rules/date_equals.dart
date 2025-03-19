import 'package:routed/src/validation/abstract_rule.dart';

class DateEqualsRule extends AbstractValidationRule {
  @override
  String get name => 'date_equals';
  @override
  String message(dynamic value, [List<String>? options]) {
    if (options != null && options.isNotEmpty) {
      return 'The field must be equal to ${options[0]}.';
    }
    return 'The field must be equal to the specified date.';
  }

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null || options == null || options.isEmpty) return false;

    final compareDate = DateTime.tryParse(options[0]);
    final thisDate = DateTime.tryParse(value.toString());

    if (compareDate == null || thisDate == null) return false;

    return thisDate.isAtSameMomentAs(compareDate);
  }
}
