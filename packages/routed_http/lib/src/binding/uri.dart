// ignore_for_file: implementation_imports
import 'package:routed/routed.dart';
import 'package:routed/src/validation/validator.dart';

import 'binding.dart';

/// Binds URI parameters to a given instance and validates them.
class UriBinding extends Binding {
  @override
  String get name => 'uri';

  @override
  MimeType? get mimeType => null;

  @override
  Future<T> bind<T>(EngineContext context, T instance) async {
    if (instance is Map) {
      for (final entry in context.params.entries) {
        final values = entry.value as List;
        instance[entry.key] = values.isEmpty ? null : values.first;
      }
    } else if (instance is Bindable) {
      final data = <String, dynamic>{};
      for (final entry in context.params.entries) {
        final values = entry.value as List;
        data[entry.key] = values.isEmpty ? null : values.first;
      }
      instance.bind(data);
    }
    return instance;
  }

  @override
  Future<void> validate(
    EngineContext context,
    Map<String, String> rules, {
    bool bail = false,
    Map<String, String>? messages,
  }) async {
    final registry = requireValidationRegistry(context.container);
    final validator = Validator.make(
      rules,
      registry: registry,
      bail: bail,
      messages: messages,
    );
    final errors = validator.validate(context.params);
    if (errors.isNotEmpty) {
      throw ValidationError(errors);
    }
  }
}
