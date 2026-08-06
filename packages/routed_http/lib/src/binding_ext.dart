import 'package:routed/routed.dart';

/// Binding helpers for [EngineContext] — migrated from `routed`
/// `src/context/binding.dart` per refactor.md §16.2.
extension RoutedHttpBinding on EngineContext {
  bool get hasBindingSupport => true;
}
