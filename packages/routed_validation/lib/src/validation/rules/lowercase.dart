import 'package:routed_validation/src/validation/rule.dart';

/// Validates that a value is equal to its lowercase representation.
class LowercaseRule extends ValidationRule {
  @override
  String get name => 'lowercase';

  @override
  String message(dynamic value, [List<String>? options]) =>
      'The field must be lowercase.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null) return false;
    return value.toString() == value.toString().toLowerCase();
  }
}
