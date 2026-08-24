import 'package:routed_core/routed_core.dart'
    show ConfigStore, Container, NamedRegistry;

import 'package:routed_validation/src/validation/rule.dart';
import 'package:routed_validation/src/validation/rules/rules.dart';

/// Factory function that creates a fresh validation rule instance.
typedef ValidationRuleFactory = ValidationRule Function();

/// Returns the validation registry configured in [container].
///
/// When the container has a [ConfigStore] but no registry, this function
/// installs and returns [ValidationRuleRegistry.defaults]. A container without
/// a configuration store is considered unconfigured and throws [StateError].
ValidationRuleRegistry requireValidationRegistry(Container container) {
  if (container.has<ValidationRuleRegistry>()) {
    return container.get<ValidationRuleRegistry>();
  }
  if (!container.has<ConfigStore>()) {
    throw StateError('ValidationRuleRegistry not found in container');
  }
  final registry = ValidationRuleRegistry.defaults();
  container.instance<ValidationRuleRegistry>(registry);
  return registry;
}

final List<ValidationRuleFactory> _defaultRuleFactories = [
  NullableRule.new,
  RequiredRule.new,
  InRule.new,
  MaxLengthRule.new,
  MinLengthRule.new,
  IntRule.new,
  DoubleRule.new,
  UuidRule.new,
  DateRule.new,
  EmailRule.new,
  NumericRule.new,
  SlugRule.new,
  StringRule.new,
  UrlRule.new,
  WordRule.new,
  ArrayRule.new,
  FileRule.new,
  MaxFileSizeRule.new,
  AllowedMimeTypesRule.new,
  MinRule.new,
  MaxRule.new,
  AcceptedRule.new,
  ActiveUrlRule.new,
  AfterRule.new,
  AlphaRule.new,
  AlphaDashRule.new,
  AlphaNumRule.new,
  BeforeRule.new,
  BetweenRule.new,
  BooleanRule.new,
  ConfirmedRule.new,
  DateFormatRule.new,
  DifferentRule.new,
  DifferentTimezoneRule.new,
  DigitsRule.new,
  DigitsBetweenRule.new,
  IpRule.new,
  Ipv4Rule.new,
  Ipv6Rule.new,
  JsonRule.new,
  AsciiRule.new,
  DoesntStartWithRule.new,
  DoesntEndWithRule.new,
  EndsWithRule.new,
  HexColorRule.new,
  LowercaseRule.new,
  NotInRule.new,
  NotRegexRule.new,
  SameRule.new,
  StartsWithRule.new,
  UppercaseRule.new,
  UlidRule.new,
  DecimalRule.new,
  GreaterThanRule.new,
  GreaterThanOrEqualRule.new,
  LessThanRule.new,
  LessThanOrEqualRule.new,
  MultipleOfRule.new,
  SameSizeRule.new,
  ContainsRule.new,
  DistinctRule.new,
  InArrayRule.new,
  ListRule.new,
  RequiredArrayKeysRule.new,
  DateEqualsRule.new,
  AfterOrEqualRule.new,
  BeforeOrEqualRule.new,
  FileBetweenRule.new,
  FileDimensionsRule.new,
  FileExtensionsRule.new,
];

/// Typed registry of validation rule factories.
///
/// Use [ValidationRuleRegistry.defaults] for the built-in catalog, or create
/// an empty registry when an application wants an allow-list of rules. Calling
/// [register] for an existing name replaces that factory, which makes it
/// possible to customize a built-in rule without changing rule strings.
class ValidationRuleRegistry extends NamedRegistry<ValidationRuleFactory> {
  /// Creates an empty rule registry.
  ValidationRuleRegistry();

  /// Creates a registry populated with all built-in rules.
  ValidationRuleRegistry.defaults() {
    _registerDefaults();
  }

  /// Copies the entries from [source] into a new registry.
  ValidationRuleRegistry.clone(ValidationRuleRegistry source) {
    for (final name in source.entryNames) {
      final factory = source.getEntry(name);
      if (factory != null) {
        registerEntry(name, factory);
      }
    }
  }

  /// Registers [factory] under the name returned by its rule instance.
  ///
  /// The factory is invoked once to discover its name and again whenever the
  /// registry resolves it. A factory should therefore be side-effect free and
  /// return an independent rule instance.
  void register(ValidationRuleFactory factory) {
    final rule = factory();
    registerEntry(rule.name, factory);
  }

  /// Resolves the factory registered under [name].
  ValidationRuleFactory? resolve(String name) => getEntry(name);

  /// Whether a rule factory is registered under [name].
  bool contains(String name) => containsEntry(name);

  /// Names of all registered validation rules.
  Iterable<String> get names => entryNames;

  void _registerDefaults() {
    _defaultRuleFactories.forEach(register);
  }
}

/// A type definition for a validation rule with optional parameters.
typedef RuleWithOptions = ({ValidationRule rule, List<String>? options});

/// Parses serialized field rules into structured rule instances.
///
/// Each [rules] value contains rule names separated by `|`. A rule may have
/// comma-separated options after `:`; for example, `between:1,10`.
///
/// Uses [registry] to resolve each rule name. Unknown names throw an
/// [Exception], so configuration errors are detected before validation starts.
/// Returns one [RuleWithOptions] record per field and preserves declaration
/// order within each field.
Map<String, List<RuleWithOptions>> parseRules(
  Map<String, String> rules,
  ValidationRuleRegistry registry,
) {
  final parsedRules = <String, List<RuleWithOptions>>{};

  rules.forEach((field, ruleString) {
    final ruleParts = ruleString.split('|');
    final fieldRules = <RuleWithOptions>[];

    for (final part in ruleParts) {
      final ruleAndOptions = part.split(':');
      final ruleName = ruleAndOptions[0];
      final options = ruleAndOptions.length > 1
          ? ruleAndOptions[1].split(',')
          : null;

      final factory = registry.resolve(ruleName);
      if (factory != null) {
        fieldRules.add((rule: factory(), options: options));
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
  /// Constructs a [Validator] with a map of parsed rules.
  Validator(
    this._rules, {
    required this.registry,
    this.bail = false,
    Map<String, String>? messages,
  }) : _messages = messages;
  final Map<String, List<RuleWithOptions>> _rules;

  /// Registry used to resolve rules when the validator was created.
  final ValidationRuleRegistry registry;

  /// Indicates if the validator should stop on the first rule failure.
  final bool bail;

  final Map<String, String>? _messages;

  /// Factory method to create a [Validator] from a map of string rules.
  ///
  /// The input [rules] map contains field names as keys and rule strings as values.
  /// This method parses the rules and constructs a [Validator] instance.
  // Keep the static factory name for source compatibility with existing apps.
  // ignore: prefer_constructors_over_static_methods
  static Validator make(
    Map<String, String> rules, {
    required ValidationRuleRegistry registry,
    bool bail = false,
    Map<String, String>? messages,
  }) {
    final parsedRules = parseRules(rules, registry);
    return Validator(
      parsedRules,
      registry: registry,
      bail: bail,
      messages: messages,
    );
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
      var fieldHasError = false;

      for (final validatorWithOptions in validators) {
        final validator = validatorWithOptions.rule;

        if (validator is ContextAwareValidationRule) {
          validator.setContextValues(data);
        }

        final validated = validator.validate(
          data[field],
          validatorWithOptions.options,
        );
        if (!validated) {
          final key = '$field.${validator.name}';
          final overrideMessage = _messages?[key] ?? _messages?[validator.name];
          final message =
              overrideMessage ??
              validator.message(data[field], validatorWithOptions.options);

          if (message.isNotEmpty) {
            errors.putIfAbsent(field, () => []);
            errors[field]!.add(message);
          }
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
