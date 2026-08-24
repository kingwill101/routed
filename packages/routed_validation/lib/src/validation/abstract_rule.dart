import 'package:routed_validation/src/validation/rule.dart';

/// Base class for stateless rules that validate a value with a predicate.
///
/// Subclasses provide a stable [ValidationRule.name], a user-facing
/// [ValidationRule.message], and the predicate in [validate]. Use
/// [ContextAwareValidationRule] instead when a rule must compare the current
/// value with other fields in the same input map.
abstract class AbstractValidationRule extends ValidationRule {
  @override
  String get name;

  @override
  String message(dynamic value, [List<String>? options]);

  @override
  bool validate(dynamic value, [List<String>? options]);
}
