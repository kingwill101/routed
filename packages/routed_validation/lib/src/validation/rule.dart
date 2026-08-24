/// Exports the core contracts for implementing named validation rules.
library;

export 'context_aware_rule.dart';

/// Contract implemented by every named validation rule.
abstract class ValidationRule {
  /// The normalized name used in validation rule strings.
  ///
  /// Names should be concise, stable, and unique within a
  /// `ValidationRuleRegistry`. Registry lookup trims whitespace and is
  /// case-insensitive.
  String get name;

  /// Returns the default message for a failed validation.
  ///
  /// [value] is the value that failed and [options] are the parsed rule
  /// options. Return an empty string when a failed rule should not add an error
  /// entry; `Validator` still treats the rule as failed for bail behavior.
  String message(dynamic value, [List<String>? options]);

  /// The input values made available to a context-aware rule.
  ///
  /// Stateless rules return `null`. Subclasses of
  /// `ContextAwareValidationRule` expose the current input map after
  /// `ContextAwareValidationRule.setContextValues` has been called.
  Map<String, dynamic>? get contextValues => null;

  /// Returns whether [value] satisfies this rule.
  ///
  /// [options] contains rule parameters parsed from the rule string. A rule
  /// should return `false` for a missing value or malformed options unless it
  /// explicitly defines different behavior, as `Validator` does not catch
  /// validation failures as exceptions.
  bool validate(dynamic value, [List<String>? options]);
}
