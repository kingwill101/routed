import 'package:routed/routed.dart';

/// View helpers for [EngineContext] — moved from `routed` to `routed_view`
/// per refactor.md §16.2. Initially a skeleton; render helpers remain in
/// `routed` until PR J extracts them as extensions.
extension RoutedViewContext on EngineContext {
  /// Placeholder view extension to establish package boundary.
  /// Real `view`/`trans` helpers will migrate here.
  bool get hasViewSupport => true;
}
