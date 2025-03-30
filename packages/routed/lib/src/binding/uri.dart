import 'package:routed/routed.dart';
import 'package:routed/src/binding/binding.dart';
import 'package:routed/src/validation/validator.dart';

/// A class that binds URI parameters to a given instance and validates them.
class UriBinding extends Binding {
  /// The name of the binding, which is 'uri'.
  @override
  String get name => 'uri';

  /// Binds URI parameters from the [context] to the [instance].
  ///
  /// If the [instance] is a [Map], it iterates over the entries in [context.params]
  /// and assigns the first value of each entry to the corresponding key in the [instance].
  /// If the entry value is empty, it assigns `null` to the key.
  ///
  /// [context] - The engine context containing the parameters to bind.
  /// [instance] - The instance to which the parameters will be bound.
  @override
  Future<void> bind(EngineContext context, dynamic instance) async {
    if (instance is Map) {
      for (final entry in context.params.entries) {
        final values = entry.value as List;
        instance[entry.key] = values.isEmpty ? null : values.first;
      }
    }
  }

  /// Validates the URI parameters in the [context] against the provided [rules].
  ///
  /// Creates a [Validator] using the [rules] and validates the parameters in [context.params].
  /// If there are validation errors, it throws a [ValidationError] with the list of errors.
  ///
  /// [context] - The engine context containing the parameters to validate.
  /// [rules] - A map of validation rules to apply to the parameters.
  @override
  Future<void> validate(EngineContext context, Map<String, String> rules,
      {bool bail = false}) async {
    final validator = Validator.make(rules, bail: bail);
    final errors = validator.validate(context.params);

    if (errors.isNotEmpty) {
      throw ValidationError(errors);
    }
  }
}
