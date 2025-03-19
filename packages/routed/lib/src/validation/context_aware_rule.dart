import 'package:routed/src/validation/rule.dart';

abstract class ContextAwareValidationRule extends ValidationRule {
  Map<String, dynamic> _contextValues = {};

  /// Sets the context values that should be used in the validation
  void setContextValues(Map<String, dynamic> values) {
    _contextValues = values;
  }

  @override
  get contextValues => _contextValues;
}
