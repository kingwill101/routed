import 'package:routed_validation/src/validation/rule.dart';

/// Base class for rules whose validation is implemented by a simple predicate.
abstract class AbstractValidationRule extends ValidationRule {
  @override
  String get name;

  @override
  String message(dynamic value, [List<String>? options]);

  @override
  bool validate(dynamic value, [List<String>? options]);
}
