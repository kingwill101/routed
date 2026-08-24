import 'package:routed_core/routed_core.dart';

import 'package:routed_http/src/binding/binding.dart';

/// Binding helpers for [EngineContext] — migrated from `routed`
/// `src/context/binding.dart` per refactor.md §16.2.
extension RoutedHttpBinding on EngineContext {
  /// Whether the routed HTTP binding extensions are available.
  bool get hasBindingSupport => true;

  /// Binds [instance] using [binding].
  Future<T> bindWith<T>(T instance, Binding binding) =>
      binding.bind(this, instance);
}
