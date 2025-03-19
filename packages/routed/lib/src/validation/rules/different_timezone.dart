import 'package:routed/src/validation/abstract_rule.dart';

class DifferentTimezoneRule extends AbstractValidationRule {
  @override
  String get name => 'different_timezone';
  @override
  String message(dynamic value, [List<String>? options]) {
    if (options != null && options.isNotEmpty) {
      return 'The field must have a different timezone than ${options[0]}.';
    }
    return 'The field must have a different timezone than the specified value.';
  }

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null || options == null || options.isEmpty) return false;

    // Need to use TimeZone package, skipping for simplicity.

    return false;
  }
}
