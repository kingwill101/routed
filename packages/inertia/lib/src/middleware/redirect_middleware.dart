import '../core/inertia_request.dart';
import '../core/inertia_response.dart';
import 'inertia_middleware.dart';

/// Middleware that adjusts redirect status codes for Inertia requests
class RedirectMiddleware extends InertiaMiddleware {
  @override
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
