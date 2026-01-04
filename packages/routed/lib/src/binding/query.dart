import 'package:routed/src/binding/binding.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/validation/validator.dart';

/// A class that handles the binding and validation of query parameters.
class QueryBinding extends Binding {
  /// The name of the binding, which is 'query'.
  @override
  String get name => 'query';

  @override
  MimeType? get mimeType => null;

  /// Validates the query parameters against the provided rules.
  ///
  /// This method uses a [Validator] to check the query parameters stored in
  /// the [EngineContext]'s query cache. If there are any validation errors,
  /// a [ValidationError] is thrown.
  ///
  /// - Parameters:
  ///   - context: The [EngineContext] containing the query parameters to validate.
  ///   - rules: A [Map] of validation rules to apply to the query parameters.
  @override
  Future<void> validate(
    EngineContext context,
    Map<String, String> rules, {
    bool bail = false,
    Map<String, String>? messages,
  }) async {
    // Create a validator with the provided rules.
    final validator = Validator.make(rules, bail: bail, messages: messages);

    // Validate the query parameters in the context's query cache.
    final errors = validator.validate(context.queryCache);

    // If there are any validation errors, throw a ValidationError.
    if (errors.isNotEmpty) {
      throw ValidationError(errors);
    }
  }

  /// Binds the query parameters from the context to the provided instance.
  ///
  /// This method takes the query parameters stored in the [EngineContext]'s
  /// query cache and binds them to the provided [instance] if it is a [Map].
  ///
  /// - Parameters:
  ///   - context: The [EngineContext] containing the query parameters to bind.
  ///   - instance: The instance to which the query parameters will be bound.
  @override
  Future<T> bind<T>(EngineContext context, T instance) async {
    // Check if the instance is a Map.
    if (instance is Map) {
      // Iterate over the entries in the context's query cache.
      for (final entry in context.queryCache.entries) {
        // Bind each query parameter to the instance.
        instance[entry.key] = entry.value;
      }
    } else if (instance is Bindable) {
      instance.bind(context.queryCache);
    }
    return instance;
  }
}
