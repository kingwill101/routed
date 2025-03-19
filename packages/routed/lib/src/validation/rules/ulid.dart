import 'package:routed/src/validation/rule.dart';

class UlidRule extends ValidationRule {
  @override
  String get name => 'ulid';

  @override
  String message(dynamic value, [List<String>? options]) =>
      'The field must be a valid ULID.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null) return false;
    return RegExp(r'^[0-9A-Z]{26}$').hasMatch(value.toString());
  }
}
