import 'dart:async';

import 'package:server_auth/src/core/exceptions.dart';

/// Maximum UTF-16 code-unit length accepted for a limiter identifier.
///
/// Endpoint-specific resolvers should normally return substantially shorter
/// canonical or keyed-hashed values. The host applies this absolute bound so
/// custom plugins cannot accidentally feed unbounded request data into a
/// limiter backend.
const int authRateLimitIdentifierMaximumLength = 256;

/// Applies the common safety boundary for endpoint-derived limiter keys.
///
/// Empty, overlong, or control-character-bearing values are discarded. The
/// function does not lowercase or otherwise reinterpret identifiers because
/// that canonicalization belongs to the endpoint's typed identifier policy.
String? normalizeAuthRateLimitIdentifier(String? value) {
  if (value == null) return null;
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized.length > authRateLimitIdentifierMaximumLength ||
      normalized.runes.any((rune) => rune <= 0x1f || rune == 0x7f)) {
    return null;
  }
  return normalized;
}

/// The externally reachable authentication operation being rate limited.
enum AuthRateLimitAction {
  /// A credentials or email sign-in attempt.
  signIn,

  /// A password verification that refreshes a sensitive-action proof.
  reauthentication,

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

  /// A reauthenticated request to change the current email address.
  emailChangeRequest,

  /// Consumption of an email-change confirmation token.
  emailChangeConfirm,

  /// Removal of a linked external authentication identity.
  accountUnlink,

  /// Verification and linking of an external authentication identity.
  accountLink,

  /// A reauthenticated self-service account deletion request.
  accountDeletion,
}

/// Stable namespaced identifier for a rate-limited auth operation.
final class AuthRateLimitOperation {
  /// Creates a namespaced operation from [namespace] and [name].
  const AuthRateLimitOperation(this.namespace, this.name)
    : assert(namespace != '', 'namespace must not be empty'),
      assert(name != '', 'name must not be empty');

  /// Creates the core operation corresponding to [action].
  factory AuthRateLimitOperation.core(AuthRateLimitAction action) =>
      AuthRateLimitOperation('core', action.name);

  /// Namespace that owns the operation.
  final String namespace;

  /// Stable name of the operation within [namespace].
  final String name;

  /// Fully qualified operation identifier.
  String get id => '$namespace.$name';

  /// Legacy core action represented by this operation, if one exists.
  AuthRateLimitAction? get legacyAction {
    if (namespace != 'core') return null;
    for (final action in AuthRateLimitAction.values) {
      if (action.name == name) return action;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is AuthRateLimitOperation &&
      other.namespace == namespace &&
      other.name == name;

  @override
  int get hashCode => Object.hash(namespace, name);

  @override
  String toString() => id;
}

/// The non-secret context supplied to an auth rate limiter.
///
/// The request deliberately contains no password, OAuth code, bearer token,
/// verification token, or other credential secret. [identifier] is suitable
/// for a limiter key (for example, an email address or username), but callers
/// must still treat it as private user input.
final class AuthRateLimitRequest<TContext> {
  /// Creates a request using the deprecated core [action] field.
  @Deprecated('Use AuthRateLimitRequest.operation with a namespaced operation.')
  const AuthRateLimitRequest({
    required AuthRateLimitAction action,
    required this.providerId,
    required this.context,
    this.identifier,
  }) : _legacyAction = action,
       _operation = null;

  /// Creates a request for a namespaced [operation].
  const AuthRateLimitRequest.operation({
    required AuthRateLimitOperation operation,
    required this.providerId,
    required this.context,
    this.identifier,
  }) : _operation = operation,
       _legacyAction = null;

  final AuthRateLimitOperation? _operation;
  final AuthRateLimitAction? _legacyAction;

  /// Operation being checked by the limiter.
  AuthRateLimitOperation get operation =>
      _operation ?? AuthRateLimitOperation.core(_legacyAction!);

  /// Legacy core action, when this request represents one.
  @Deprecated('Use operation instead.')
  AuthRateLimitAction get action {
    final value = _legacyAction ?? operation.legacyAction;
    if (value == null) {
      throw StateError('${operation.id} has no legacy AuthRateLimitAction.');
    }
    return value;
  }

  /// Identifier of the provider handling the operation.
  final String providerId;

  /// Host context used by the limiter to derive trusted request attributes.
  final TContext context;

  /// Optional non-secret identifier such as an email or username.
  final String? identifier;
}

/// Result returned by an [AuthRateLimiter].
final class AuthRateLimitDecision {
  /// Creates an allowed decision.
  const AuthRateLimitDecision.allow()
    : allowed = true,
      retryAfter = Duration.zero;

  /// Creates a blocked decision with the suggested retry delay.
  const AuthRateLimitDecision.block({required this.retryAfter})
    : allowed = false;

  /// Whether the operation may continue.
  final bool allowed;

  /// Duration the caller should wait before retrying.
  final Duration retryAfter;
}

/// Application-owned policy for throttling authentication operations.
///
/// Implementations commonly combine a trusted client address from `context`
/// with [AuthRateLimitRequest.identifier]. Do not log or persist the request
/// object as a whole: its context and identifier may contain private data.
abstract interface class AuthRateLimiter<TContext> {
  /// Evaluates whether [request] may proceed.
  FutureOr<AuthRateLimitDecision> check(AuthRateLimitRequest<TContext> request);
}

/// Raised when an auth operation is rejected by [AuthRateLimiter].
final class AuthRateLimitException extends AuthFlowException {
  /// Creates a rate-limit exception with [retryAfter].
  AuthRateLimitException({required this.retryAfter}) : super('rate_limited');

  /// Suggested delay before another attempt.
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
