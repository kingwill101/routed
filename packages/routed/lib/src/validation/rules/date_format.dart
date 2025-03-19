import 'package:routed/src/validation/rule.dart';
import 'package:intl/intl.dart';

/// Validation rule that checks if a date matches a given format.
class DateFormatRule extends ValidationRule {
  @override
  String get name => 'date_format';

  @override
  String message(dynamic value, [List<String>? options]) {
    if (options != null && options.isNotEmpty) {
      return 'The field does not match the format ${options[0]}.';
    }
    return 'The field does not match the required date format.';
  }

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null || options == null || options.isEmpty) return false;

    try {
      DateFormat(options[0]).parseStrict(value.toString());
      return true;
    } catch (e) {
      return false;
    }
  }
}
