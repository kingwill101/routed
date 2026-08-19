import 'dart:async';

import 'exceptions.dart';

/// The externally reachable authentication operation being rate limited.
enum AuthRateLimitAction {
  /// A credentials or email sign-in attempt.
  signIn,

  /// A new credentials registration attempt.
  register,

  /// A request that sends an email sign-in challenge.
  emailVerification,

  /// The callback that consumes an email sign-in challenge.
  emailCallback,

  /// The beginning of an OAuth authorization flow.
  oauthStart,

  /// The OAuth callback that exchanges an authorization code.
  oauthCallback,

  /// A provider-specific callback such as a Telegram login callback.
  customCallback,

  /// A request to deliver a password-reset message.
  passwordResetRequest,

  /// A request to consume a password-reset token and change a password.
  passwordResetConfirm,

  /// A TOTP, recovery-code, or step-up verification attempt.
  twoFactor,
}

/// The non-secret context supplied to an auth rate limiter.
///
/// The request deliberately contains no password, OAuth code, bearer token,
/// verification token, or other credential secret. [identifier] is suitable
/// for a limiter key (for example, an email address or username), but callers
/// must still treat it as private user input.
final class AuthRateLimitRequest<TContext> {
  const AuthRateLimitRequest({
    required this.action,
    required this.providerId,
    required this.context,
    this.identifier,
  });

  final AuthRateLimitAction action;
  final String providerId;
  final TContext context;
  final String? identifier;
}

/// Result returned by an [AuthRateLimiter].
final class AuthRateLimitDecision {
  const AuthRateLimitDecision.allow()
    : allowed = true,
      retryAfter = Duration.zero;

  const AuthRateLimitDecision.block({required this.retryAfter})
    : allowed = false;

  final bool allowed;
  final Duration retryAfter;
}

/// Application-owned policy for throttling authentication operations.
///
/// Implementations commonly combine a trusted client address from [context]
/// with [AuthRateLimitRequest.identifier]. Do not log or persist the request
/// object as a whole: its context and identifier may contain private data.
abstract interface class AuthRateLimiter<TContext> {
  FutureOr<AuthRateLimitDecision> check(AuthRateLimitRequest<TContext> request);
}

/// Raised when an auth operation is rejected by [AuthRateLimiter].
final class AuthRateLimitException extends AuthFlowException {
  AuthRateLimitException({required this.retryAfter}) : super('rate_limited');

  final Duration retryAfter;
}

/// Applies an optional auth rate limiter and raises a stable flow error when
/// the operation is blocked.
Future<void> enforceAuthRateLimit<TContext>({
  required AuthRateLimiter<TContext>? limiter,
  required AuthRateLimitRequest<TContext> request,
}) async {
  if (limiter == null) return;
  final decision = await limiter.check(request);
  if (!decision.allowed) {
    throw AuthRateLimitException(retryAfter: decision.retryAfter);
  }
}
