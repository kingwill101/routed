import '../core/inertia_request.dart';
import '../core/inertia_response.dart';
import 'inertia_middleware.dart';

/// Middleware for handling errors in Inertia responses
class ErrorHandlingMiddleware extends InertiaMiddleware {
  ErrorHandlingMiddleware({this.onError});
  final InertiaResponse Function(Object error, StackTrace stack)? onError;

  @override
  Future<InertiaResponse> handle(
    InertiaRequest request,
    InertiaHandler next,
  ) async {
    try {
      return await next(request);
    } catch (error, stack) {
      if (onError != null) {
        return onError!(error, stack);
      }
      rethrow;
    }
  }
}
