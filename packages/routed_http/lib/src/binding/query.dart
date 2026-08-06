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
    throw UnimplementedError('validation moved to routed_validation');
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
