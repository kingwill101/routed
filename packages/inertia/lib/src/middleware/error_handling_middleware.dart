library;

import '../core/inertia_request.dart';
import '../core/inertia_response.dart';
import 'inertia_middleware.dart';

/// Provides error handling for Inertia middleware chains.
///
/// ```dart
/// final middleware = ErrorHandlingMiddleware(
///   onError: (error, stack) => InertiaResponse.location('/error'),
/// );
/// ```
class ErrorHandlingMiddleware extends InertiaMiddleware {
  /// Creates an error handling middleware.
  ErrorHandlingMiddleware({this.onError});

  /// Optional error handler that converts errors to responses.
  final InertiaResponse Function(Object error, StackTrace stack)? onError;

  @override
  /// Catches errors and delegates to [onError] when provided.
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
