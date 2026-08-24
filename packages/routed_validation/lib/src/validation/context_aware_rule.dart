import 'package:routed_validation/src/validation/rule.dart';

/// Base class for rules that compare a value with other input fields.
abstract class ContextAwareValidationRule extends ValidationRule {
  Map<String, dynamic> _contextValues = {};

  /// Sets the context values that should be used during validation.
  // This method is retained as part of the rule extension contract.
  // ignore: use_setters_to_change_properties
  void setContextValues(Map<String, dynamic> values) {
    _contextValues = values;
  }

  @override
  Map<String, dynamic> get contextValues => _contextValues;
}
