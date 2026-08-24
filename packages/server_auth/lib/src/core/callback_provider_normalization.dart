import 'package:server_auth/src/core/models.dart' show AuthUser;
import 'package:server_auth/src/core/providers.dart' show CallbackResult;

/// Framework-agnostic normalized outcome for callback-provider results.
class AuthCallbackProviderOutcome {
  /// Creates a successful outcome with an authenticated [user].
  ///
  /// [redirectUrl] is optional, and successful outcomes have no [errorCode].
  const AuthCallbackProviderOutcome.success({
    required this.user,
    this.redirectUrl,
  }) : errorCode = null;

  /// Creates a failed outcome preserving the supplied [errorCode].
  ///
  /// The code may be an empty string; failed outcomes have no user or redirect.
  const AuthCallbackProviderOutcome.failure(this.errorCode)
    : user = null,
      redirectUrl = null;

  /// Authenticated user when callback succeeds.
  final AuthUser? user;

  /// Optional redirect URL when callback succeeds.
  final String? redirectUrl;

  /// Canonical auth error code when callback fails.
  final String? errorCode;

  /// Whether callback resolution succeeded.
  bool get isSuccess => user != null;
}

/// Normalizes callback-provider [result] into a stable success/failure shape.
///
/// Successful results preserve their user and redirect. Failed results preserve
/// a non-null error, while a null error uses [fallbackErrorCode].
AuthCallbackProviderOutcome normalizeAuthCallbackProviderResult(
  CallbackResult result, {
  String fallbackErrorCode = 'callback_failed',
}) {
  if (!result.isSuccess) {
    return AuthCallbackProviderOutcome.failure(
      result.error ?? fallbackErrorCode,
    );
  }
  return AuthCallbackProviderOutcome.success(
    user: result.user,
    redirectUrl: result.redirect,
  );
}
