/// Request validation and binding primitives for Routed applications.
///
/// The package exposes two layers:
///
/// * `Validator` validates a map with a typed `ValidationRuleRegistry`.
/// * `ValidationContext` adds request-aware `validate` and `bind` helpers to
///   Routed's `EngineContext`.
///
/// Rules use a compact string syntax. Separate rules with `|` and pass
/// comma-separated options after `:`:
///
/// ```dart
/// final validator = Validator.make(
///   {
///     'email': 'required|email',
///     'age': 'required|int|min:18',
///   },
///   registry: ValidationRuleRegistry.defaults(),
/// );
///
/// final errors = validator.validate({'email': 'bad', 'age': '16'});
/// // {'email': ['This field must be a valid email address.'], ...}
/// ```
///
/// Register an application-specific rule by adding its factory to a registry,
/// then pass that registry to `Validator.make` or install it in the Routed
/// container used by `ValidationContext.validate`.
library;

export 'src/validation/abstract_rule.dart';
export 'src/validation/context.dart';
export 'src/validation/context_aware_rule.dart';
export 'src/validation/file.dart';
export 'src/validation/rule.dart';
export 'src/validation/rules/rules.dart';
export 'src/validation/validator.dart';
