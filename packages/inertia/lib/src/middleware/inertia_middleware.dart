import '../core/inertia_request.dart';
import '../core/inertia_response.dart';

/// Handler signature for Inertia middleware chains
typedef InertiaHandler =
    Future<InertiaResponse> Function(InertiaRequest request);

/// Base interface for Inertia middleware
abstract class InertiaMiddleware {
  Future<InertiaResponse> handle(InertiaRequest request, InertiaHandler next);
}
