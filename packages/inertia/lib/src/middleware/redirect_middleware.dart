library;

import '../core/inertia_request.dart';
import '../core/inertia_response.dart';
import 'inertia_middleware.dart';

/// Normalizes redirect status codes for Inertia requests.
///
/// ```dart
/// final middleware = RedirectMiddleware();
/// ```
class RedirectMiddleware extends InertiaMiddleware {
  @override
  /// Rewrites 302 redirects to 303 for non-GET Inertia requests.
  Future<InertiaResponse> handle(
    InertiaRequest request,
    InertiaHandler next,
  ) async {
    final response = await next(request);

    if (!request.isInertia) return response;

    final method = request.method.toUpperCase();
    final shouldRewrite =
        (method == 'PUT' || method == 'PATCH' || method == 'DELETE') &&
        response.statusCode == 302;

    if (!shouldRewrite) return response;

    return InertiaResponse(
      page: response.page,
      statusCode: 303,
      headers: response.headers,
      html: response.html,
    );
  }
}
