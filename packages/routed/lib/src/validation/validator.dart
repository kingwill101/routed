import 'package:routed/src/validation/rule.dart';
import 'package:routed/src/validation/rules/array.dart';
import 'package:routed/src/validation/rules/rules.dart';

/// A set of known validation rules used in the application.
final kKnownRules = <ValidationRule>{
  NullableRule(),
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
  MinRule(),
  MaxRule(),
  AcceptedRule(),
  ActiveUrlRule(),
  AfterRule(),
  AlphaRule(),
  AlphaDashRule(),
  AlphaNumRule(),
  BeforeRule(),
  BetweenRule(),
  BooleanRule(),
  ConfirmedRule(),
  DateFormatRule(),
  DifferentRule(),
  DigitsRule(),
  DigitsBetweenRule(),
  IpRule(),
  Ipv4Rule(),
  Ipv6Rule(),
  JsonRule(),
  AsciiRule(),
  DoesntStartWithRule(),
  DoesntEndWithRule(),
  EndsWithRule(),
  HexColorRule(),
  LowercaseRule(),
  NotInRule(),
  NotRegexRule(),
  SameRule(),
  StartsWithRule(),
  UppercaseRule(),
  UlidRule(),
  DecimalRule(),
  GreaterThanRule(),
  GreaterThanOrEqualRule(),
  LessThanRule(),
  LessThanOrEqualRule(),
  MultipleOfRule(),
  SameSizeRule(),
  ContainsRule(),
  DistinctRule(),
  InArrayRule(),
  ListRule(),
  RequiredArrayKeysRule(),
  DateEqualsRule(),
  AfterOrEqualRule(),
  BeforeOrEqualRule(),
  FileBetweenRule(),
  FileDimensionsRule(),
  FileExtensionsRule(),
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
        final theRule = rule.first;
        fieldRules.add((rule: theRule, options: options));
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

  /// Indicates if the validator should stop on the first rule failure.
  final bool bail;

  /// Constructs a [Validator] with a map of parsed rules.
  Validator(this._rules, {this.bail = false});

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
  static Validator make(Map<String, String> rules, {bool bail = false}) {
    final parsedRules = parseRules(rules);
    return Validator(parsedRules, bail: bail);
  }

  /// Validates the input [data] against the validation rules.
  ///
  /// The input [data] map contains field names as keys and their corresponding values.
  /// Returns a map where each field name is associated with a list of error messages.
  Map<String, List<String>> validate(Map<String, dynamic> data) {
    final errors = <String, List<String>>{};

    // Iterate through each rule entry to validate fields
    for (final ruleEntry in _rules.entries) {
      final field = ruleEntry.key;
      final validators = ruleEntry.value;
      bool fieldHasError = false;

      for (final validatorWithOptions in validators) {
        final validator = validatorWithOptions.rule;

        if (validator is ContextAwareValidationRule) {
          validator.setContextValues(data);
        }

        final validated =
            validator.validate(data[field], validatorWithOptions.options);
        if (!validated) {
          errors[field] = [
            validator.message(data[field], validatorWithOptions.options)
          ];
          fieldHasError = true;
          if (bail) {
            break; // Stop validating this field if bail is true
          }
        }
      }
      if (fieldHasError && bail) {
        break;
      }
    }

    return errors;
  }
}
