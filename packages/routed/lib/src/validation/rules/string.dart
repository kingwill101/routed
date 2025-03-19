import 'package:routed/src/validation/rule.dart';

/// A validation rule that checks if a given value is a valid string.
class StringRule extends ValidationRule {
  @override
  String get name => 'string';

  @override
  String message(dynamic value, [List<String>? options]) =>
      'This field must be a valid string.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null) return false;
    return value is String || value.toString().isNotEmpty;
  }
}
