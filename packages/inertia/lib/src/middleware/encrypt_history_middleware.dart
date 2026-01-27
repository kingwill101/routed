library;

import '../core/inertia_request.dart';
import '../core/inertia_response.dart';
import 'inertia_middleware.dart';

/// Enables history encryption for Inertia responses.
class EncryptHistoryMiddleware extends InertiaMiddleware {
  @override
  Future<InertiaResponse> handle(
    InertiaRequest request,
    InertiaHandler next,
  ) async {
    final response = await next(request);
    if (response.page.encryptHistory) return response;

    final updatedPage = response.page.copyWith(encryptHistory: true);
    return InertiaResponse(
      page: updatedPage,
      statusCode: response.statusCode,
      headers: response.headers,
      html: response.html,
    );
  }
}
