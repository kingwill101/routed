import 'package:routed_validation/src/validation/rule.dart';

/// Base class for rules that compare a value with other input fields.
///
/// `Validator` supplies the complete input map before it invokes
/// `ValidationRule.validate`. Direct callers should call `setContextValues`
/// first. The map is replaced for each validation pass; a rule should treat it
/// as read-only and return `false` when a referenced field or option is absent.
abstract class ContextAwareValidationRule extends ValidationRule {
  Map<String, dynamic> _contextValues = {};

  /// Sets the input values available to this rule during validation.
  ///
  /// The values are keyed by field name and are normally supplied by
  /// `Validator`. This method replaces the previous context rather than
  /// merging with it.
  // This method is retained as part of the rule extension contract.
  // ignore: use_setters_to_change_properties
  void setContextValues(Map<String, dynamic> values) {
    _contextValues = values;
  }

  @override
  Map<String, dynamic> get contextValues => _contextValues;
}
