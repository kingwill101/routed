import 'providers.dart' show CallbackResult;
import 'models.dart' show AuthUser;

/// Framework-agnostic normalized outcome for callback-provider results.
class AuthCallbackProviderOutcome {
  const AuthCallbackProviderOutcome.success({
    required this.user,
    this.redirectUrl,
  }) : errorCode = null;

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
    user: result.user!,
    redirectUrl: result.redirect,
  );
}
