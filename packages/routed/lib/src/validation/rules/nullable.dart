import 'package:routed/src/validation/rule.dart';

/// A validation rule that allows null values.  It effectively removes any
/// other validation rules if the value is null.  This rule should be listed
/// first if you want to allow nulls.

class NullableRule extends ValidationRule {
  @override
  String get name => 'nullable';

  @override
  String message(dynamic value, [List<String>? options]) => '';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    return value == null;
  }
}
