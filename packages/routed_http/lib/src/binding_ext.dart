import 'package:routed_core/routed_core.dart';

import 'binding/binding.dart';

/// Binding helpers for [EngineContext] — migrated from `routed`
/// `src/context/binding.dart` per refactor.md §16.2.
extension RoutedHttpBinding on EngineContext {
  bool get hasBindingSupport => true;

  Future<T> bindWith<T>(T instance, Binding binding) =>
      binding.bind(this, instance);
}
