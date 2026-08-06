import 'package:routed/routed.dart';

import 'http/negotiation.dart';

/// HTTP helpers for [EngineContext] — migrated from `routed`
/// `src/context/negotiation.dart` and `src/http/*` per refactor.md §16.2.
extension RoutedHttpNegotiation on EngineContext {
  bool get hasHttpSupport => true;

  NegotiatedMediaType? httpNegotiatedContentType(List<String> available) {
    return ContentNegotiator.negotiate(
      requestHeader('accept'),
      available,
    );
  }
}
