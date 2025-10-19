import '../exceptions/http.dart' show HttpException;
import 'view_mixin.dart';

/// Mixin that provides success URL functionality
mixin SuccessFailureUrlMixin on ViewMixin {
  /// URL to redirect to after successful form processing
  String? get successUrl => null;

  /// URL to redirect to after failed form processing
  String? get failureUrl => null;

  /// Get success URL for an object
  String getSuccessUrl([dynamic object]) {
    return successUrl ?? '/';
  }

  /// Get failure URL for an object
  String getFailureUrl([dynamic object]) {
    return failureUrl ?? '/';
  }

  /// Redirect to success URL
  Future<void> redirectToSuccess([dynamic object]) async {
    await redirect(getSuccessUrl(object));
  }

  /// Redirect to failure URL
  Future<void> redirectToFailure([dynamic object]) async {
    await redirect(getFailureUrl(object));
  }

  /// Called on successful operation
  Future<void> onSuccess([dynamic object]) async {
    if (successUrl != null) {
      await redirectToSuccess(object);
    } else {
      // Default success response
      await sendJson({
        'success': true,
        'message': 'Operation completed successfully',
      });
    }
  }

  /// Called on failed operation
  Future<void> onFailure(Object error, [dynamic object]) async {
    if (failureUrl != null) {
      await redirectToFailure(object);
    } else {
      throw HttpException.badRequest(error.toString());
    }
  }
}
