// ignore_for_file: implementation_imports
import 'package:routed_core/routed_core.dart';

import '../context/form_cache.dart';
import 'binding.dart';

/// Handles binding and validation of query parameters.
class QueryBinding extends Binding {
  @override
  String get name => 'query';

  @override
  MimeType? get mimeType => null;

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
