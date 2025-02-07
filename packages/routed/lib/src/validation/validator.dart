import 'package:routed/src/validation/rule.dart';
import 'package:routed/src/validation/rules/array.dart';
import 'package:routed/src/validation/rules/rules.dart';

/// A set of known validation rules used in the application.
final kKnownRules = <ValidationRule>{
  RequiredRule(),
  InRule(),
  MaxLengthRule(),
  MinLengthRule(),
  IntRule(),
  DoubleRule(),
  UuidRule(),
  DateRule(),
  EmailRule(),
  InRule(),
  NumericRule(),
  RequiredRule(),
  SlugRule(),
  StringRule(),
  UrlRule(),
  UuidRule(),
  WordRule(),
  ArrayRule(),
  FileRule(),
  MaxFileSizeRule(),
  AllowedMimeTypesRule(),
};

/// A type definition for a validation rule with optional parameters.
typedef RuleWithOptions = ({ValidationRule rule, List<String>? options});

/// Parses a map of string rules into a structured format.
///
/// The input [rules] map contains field names as keys and rule strings as values.
/// Each rule string can contain multiple rules separated by '|', and each rule
/// can have options separated by ':'.
///
/// Returns a map where each field name is associated with a list of [RuleWithOptions].
Map<String, List<RuleWithOptions>> parseRules(Map<String, String> rules) {
  final parsedRules = <String, List<RuleWithOptions>>{};

  rules.forEach((field, ruleString) {
    final ruleParts = ruleString.split('|');
    final List<RuleWithOptions> fieldRules = [];

    for (final part in ruleParts) {
      final ruleAndOptions = part.split(':');
      final ruleName = ruleAndOptions[0];
      final options =
          ruleAndOptions.length > 1 ? ruleAndOptions[1].split(',') : null;

      final rule = kKnownRules.where((rule) => rule.name == ruleName);
      if (rule.isNotEmpty) {
        fieldRules.add((rule: rule.first, options: options));
      } else {
        throw Exception('Unknown validation rule: $ruleName');
      }
    }

    parsedRules[field] = fieldRules;
  });

  return parsedRules;
}

/// A class responsible for validating data against a set of rules.
class Validator {
  final Map<String, List<RuleWithOptions>> _rules;

  /// Constructs a [Validator] with a map of parsed rules.
  Validator(this._rules);

  /// Registers a new validation rule to the global validation system
  ///
  /// This static method adds or updates custom validation rules in [kKnownRules].
  /// When registering a rule with a name that already exists, the new rule replaces the old one.
  ///
  /// Example:
  ///
  /// Validator.registerRule(CustomPhoneRule());
  ///
  static void registerRule(ValidationRule rule) {
    kKnownRules.removeWhere((existing) => existing.name == rule.name);
    kKnownRules.add(rule);
  }

  /// Factory method to create a [Validator] from a map of string rules.
  ///
  /// The input [rules] map contains field names as keys and rule strings as values.
  /// This method parses the rules and constructs a [Validator] instance.
  static Validator make(Map<String, String> rules) {
    final parsedRules = parseRules(rules);
    return Validator(parsedRules);
  }

  /// Validates the input [data] against the validation rules.
  ///
  /// The input [data] map contains field names as keys and their corresponding values.
  /// Returns a map where each field name is associated with a list of error messages.
  Map<String, List<String>> validate(Map<String, dynamic> data) {
    final errors = <String, List<String>>{};
    for (final rule in _rules.entries) {
      for (var validator in rule.value) {
        final validated =
            validator.rule.validate(data[rule.key], validator.options);
        if (!validated) {
          errors[rule.key] = [validator.rule.message];
        }
      }
    }
    return errors;
  }
}
