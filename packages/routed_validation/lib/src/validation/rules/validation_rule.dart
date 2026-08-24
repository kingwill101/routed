/// Base class for the legacy single-method validation rule contract.
// This file is retained for consumers that import the historical path.
// ignore: one_member_abstracts
abstract class ValidationRule {
  /// Validate a value
  void validate(dynamic value);
}
