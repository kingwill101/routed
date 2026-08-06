import 'package:routed_validation/src/validation/rule.dart';

abstract class AbstractValidationRule extends ValidationRule {
  @override
  String get name;

  @override
  String message(dynamic value, [List<String>? options]);

  @override
  bool validate(dynamic value, [List<String>? options]);
}
