import 'package:routed_core/routed_core.dart';

import 'package:routed_http/src/binding/binding.dart';

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
      (instance as Bindable).bind(data);
    }
    return instance;
  }
}
