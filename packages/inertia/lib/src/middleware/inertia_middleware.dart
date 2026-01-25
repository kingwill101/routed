library;

import '../core/inertia_request.dart';
import '../core/inertia_response.dart';

/// Handler signature for Inertia middleware chains.
typedef InertiaHandler =
    Future<InertiaResponse> Function(InertiaRequest request);

/// Defines middleware interfaces for Inertia request handling.
///
/// ```dart
/// final response = await middleware.handle(request, next);
/// ```
abstract class InertiaMiddleware {
  /// Handles [request] and delegates to [next] when appropriate.
  Future<InertiaResponse> handle(InertiaRequest request, InertiaHandler next);
}
