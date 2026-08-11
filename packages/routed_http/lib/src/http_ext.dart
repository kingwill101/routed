import 'package:routed/routed.dart';

/// HTTP helpers for [EngineContext] — migrated from `routed`
/// `src/context/negotiation.dart` and `src/http/*` per refactor.md §16.2.
extension RoutedHttpNegotiation on EngineContext {
  bool get hasHttpSupport => true;

  /// Alias for negotiation helpers that will move here.
  String? httpNegotiatedContentType(List<String> available) {
    // Delegates to existing negotiation on EngineContext when available.
    return null;
  }
}
