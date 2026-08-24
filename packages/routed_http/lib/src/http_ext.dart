import 'package:routed_core/routed_core.dart';

import 'package:routed_http/src/http/negotiation.dart';

/// HTTP helpers for [EngineContext] — migrated from `routed`
/// `src/context/negotiation.dart` and `src/http/*` per refactor.md §16.2.
extension RoutedHttpNegotiation on EngineContext {
  /// Whether the routed HTTP negotiation extensions are available.
  bool get hasHttpSupport => true;

  /// Selects the best representation from [available] for this request.
  NegotiatedMediaType? httpNegotiatedContentType(List<String> available) {
    return ContentNegotiator.negotiate(requestHeader('accept'), available);
  }
}
