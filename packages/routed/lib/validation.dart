/// Validation helpers and rules for Routed.
///
/// Import this when you need access to the validator, rule definitions, or
/// validation errors without pulling the entire framework barrel.
library;

export 'src/validation/validator.dart'
    show
        ValidationRuleFactory,
        RuleWithOptions,
        parseRules,
        kKnownRuleFactories;
export 'src/validation/validation_error.dart';
export 'src/validation/rule.dart' show ValidationRule;
export 'src/validation/context_aware_rule.dart';
export 'src/validation/abstract_rule.dart';
export 'src/validation/rules/rules.dart';
