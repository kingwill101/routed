// ignore_for_file: implementation_imports
import 'package:routed/routed.dart'
    hide
        Binding,
        Bindable,
        MimeType,
        SseEvent,
        SseCodec,
        ContentNegotiator,
        NegotiatedMediaType;
import 'package:routed/src/validation/validator.dart';

import 'binding.dart';

/// Handles binding and validation of query parameters.
class QueryBinding extends Binding {
  @override
  String get name => 'query';

  @override
  MimeType? get mimeType => null;

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
    final errors = validator.validate(context.queryCache);
    if (errors.isNotEmpty) {
      throw ValidationError(errors);
    }
  }

  @override
  Future<T> bind<T>(EngineContext context, T instance) async {
    if (instance is Map) {
      for (final entry in context.queryCache.entries) {
        instance[entry.key] = entry.value;
      }
    } else if (instance is Bindable) {
      (instance as Bindable).bind(context.queryCache);
    }
    return instance;
  }
}
