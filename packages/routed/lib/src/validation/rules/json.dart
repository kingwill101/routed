import 'package:routed/src/validation/rule.dart';
import 'dart:convert';

/// Validation rule that checks if the value is a valid JSON string.
class JsonRule extends ValidationRule {
  @override
  String get name => 'json';

  @override
  String message(dynamic value, [List<String>? options]) =>
      'The field must be a valid JSON string.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null) return false;

    try {
      jsonDecode(value.toString());
      return true;
    } catch (e) {
      return false;
    }
  }
}
