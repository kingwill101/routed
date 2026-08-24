import 'package:server_auth/src/core/providers.dart';

/// Sign-in route branch selected for a request.
enum AuthSignInRouteKind {
  /// Delegates sign-in to an OAuth provider.
  oauth,

  /// Sends a magic-link sign-in request.
  email,

  /// Processes credentials sign-in.
  credentials,

  /// Reports a sign-in routing error.
  error,
}

/// Concrete sign-in routing decision used by framework adapters.
class AuthSignInRouteDecision {
  const AuthSignInRouteDecision._({
    required this.kind,
    required this.requiresCsrf,
    this.errorCode,
    this.email,
  });

  /// Creates an OAuth decision that does not require adapter CSRF handling.
  const AuthSignInRouteDecision.oauth()
    : this._(kind: AuthSignInRouteKind.oauth, requiresCsrf: false);

  /// Creates a magic-link decision for [email] that requires CSRF handling.
  const AuthSignInRouteDecision.email(String email)
    : this._(kind: AuthSignInRouteKind.email, requiresCsrf: true, email: email);

  /// Creates a credentials decision that requires CSRF handling.
  const AuthSignInRouteDecision.credentials()
    : this._(kind: AuthSignInRouteKind.credentials, requiresCsrf: true);

  /// Creates an error decision carrying [errorCode].
  ///
  /// [requiresCsrf] tells an adapter whether CSRF handling applies; it is not
  /// the result of validating a CSRF token.
  const AuthSignInRouteDecision.error(
    String errorCode, {
    bool requiresCsrf = false,
  }) : this._(
         kind: AuthSignInRouteKind.error,
         errorCode: errorCode,
         requiresCsrf: requiresCsrf,
       );

  /// Selected sign-in branch.
  final AuthSignInRouteKind kind;

  /// Stable error code, present for [AuthSignInRouteKind.error].
  final String? errorCode;

  /// Whether the adapter should perform CSRF handling for this branch.
  final bool requiresCsrf;

  /// Email selected for [AuthSignInRouteKind.email].
  final String? email;
}

/// Register route branch selected for a request.
enum AuthRegisterRouteKind {
  /// Processes credentials registration.
  credentials,

  /// Reports a registration routing error.
  error,
}

/// Concrete register routing decision used by framework adapters.
class AuthRegisterRouteDecision {
  const AuthRegisterRouteDecision._({
    required this.kind,
    required this.requiresCsrf,
    this.errorCode,
  });

  /// Creates a credentials decision that requires CSRF handling.
  const AuthRegisterRouteDecision.credentials()
    : this._(kind: AuthRegisterRouteKind.credentials, requiresCsrf: true);

  /// Creates an error decision carrying [errorCode].
  ///
  /// [requiresCsrf] tells an adapter whether CSRF handling applies.
  const AuthRegisterRouteDecision.error(
    String errorCode, {
    bool requiresCsrf = false,
  }) : this._(
         kind: AuthRegisterRouteKind.error,
         errorCode: errorCode,
         requiresCsrf: requiresCsrf,
       );

  /// Selected registration branch.
  final AuthRegisterRouteKind kind;

  /// Stable error code, present for [AuthRegisterRouteKind.error].
  final String? errorCode;

  /// Whether the adapter should perform CSRF handling for this branch.
  final bool requiresCsrf;
}

/// Callback route branch selected for a request.
enum AuthCallbackRouteKind {
  /// Completes an OAuth callback.
  oauth,

  /// Completes a magic-link callback.
  email,

  /// Delegates callback handling to a custom provider.
  custom,

  /// Reports a callback routing error.
  error,
}

/// Concrete callback routing decision used by framework adapters.
class AuthCallbackRouteDecision {
  const AuthCallbackRouteDecision._({
    required this.kind,
    this.errorCode,
    this.code,
    this.state,
    this.token,
    this.email,
  });

  /// Creates an OAuth callback decision with [code] and optional [state].
  const AuthCallbackRouteDecision.oauth({required String code, String? state})
    : this._(kind: AuthCallbackRouteKind.oauth, code: code, state: state);

  /// Creates a magic-link callback decision with [token] and [email].
  const AuthCallbackRouteDecision.email({
    required String token,
    required String email,
  }) : this._(kind: AuthCallbackRouteKind.email, token: token, email: email);

  /// Creates a custom-provider callback decision.
  const AuthCallbackRouteDecision.custom()
    : this._(kind: AuthCallbackRouteKind.custom);

  /// Creates an error decision carrying [errorCode].
  const AuthCallbackRouteDecision.error(String errorCode)
    : this._(kind: AuthCallbackRouteKind.error, errorCode: errorCode);

  /// Selected callback branch.
  final AuthCallbackRouteKind kind;

  /// Stable error code, present for [AuthCallbackRouteKind.error].
  final String? errorCode;

  /// OAuth authorization code, present for [AuthCallbackRouteKind.oauth].
  final String? code;

  /// Optional OAuth state value, preserved as supplied.
  final String? state;

  /// Magic-link token, present for [AuthCallbackRouteKind.email].
  final String? token;

  /// Email or identifier selected for [AuthCallbackRouteKind.email].
  final String? email;
}

/// Resolves sign-in branching decisions used by auth route handlers.
///
/// Missing or empty [providerId] returns `missing_provider`; a null [provider]
/// returns `unknown_provider`. OAuth takes precedence over method and CSRF
/// checks. Other providers reject exact `GET` with `method_not_allowed`, then
/// invalid CSRF with `invalid_csrf`. Magic-link requests require a non-empty
/// `email` payload and credentials providers select credentials. Other types
/// return `unsupported_provider` with CSRF required. Values are converted with
/// `toString()` and are not trimmed.
AuthSignInRouteDecision resolveAuthSignInRouteDecision({
  required String? providerId,
  required AuthProvider? provider,
  required String method,
  required Map<String, dynamic> payload,
  required bool csrfValid,
}) {
  if (providerId == null || providerId.isEmpty) {
    return const AuthSignInRouteDecision.error('missing_provider');
  }

  if (provider == null) {
    return const AuthSignInRouteDecision.error('unknown_provider');
  }

  if (provider is OAuthProvider) {
    return const AuthSignInRouteDecision.oauth();
  }

  if (method == 'GET') {
    return const AuthSignInRouteDecision.error('method_not_allowed');
  }

  if (!csrfValid) {
    return const AuthSignInRouteDecision.error(
      'invalid_csrf',
      requiresCsrf: true,
    );
  }

  if (provider is AuthMagicLinkProvider) {
    final email = _stringValue(payload['email']);
    if (email == null || email.isEmpty) {
      return const AuthSignInRouteDecision.error(
        'missing_email',
        requiresCsrf: true,
      );
    }
    return AuthSignInRouteDecision.email(email);
  }

  if (provider is CredentialsProvider) {
    return const AuthSignInRouteDecision.credentials();
  }

  return const AuthSignInRouteDecision.error(
    'unsupported_provider',
    requiresCsrf: true,
  );
}

/// Resolves register branching decisions used by auth route handlers.
///
/// Missing or empty [providerId] returns `missing_provider`, and a null
/// [provider] returns `unknown_provider`. CSRF is checked next, followed by
/// credentials-provider selection. Other types return `unsupported_provider`
/// with CSRF required.
AuthRegisterRouteDecision resolveAuthRegisterRouteDecision({
  required String? providerId,
  required AuthProvider? provider,
  required bool csrfValid,
}) {
  if (providerId == null || providerId.isEmpty) {
    return const AuthRegisterRouteDecision.error('missing_provider');
  }

  if (provider == null) {
    return const AuthRegisterRouteDecision.error('unknown_provider');
  }

  if (!csrfValid) {
    return const AuthRegisterRouteDecision.error(
      'invalid_csrf',
      requiresCsrf: true,
    );
  }

  if (provider is CredentialsProvider) {
    return const AuthRegisterRouteDecision.credentials();
  }

  return const AuthRegisterRouteDecision.error(
    'unsupported_provider',
    requiresCsrf: true,
  );
}

/// Resolves callback branching decisions used by auth route handlers.
///
/// Missing or empty [providerId] returns `missing_provider`; a null [provider]
/// returns `unknown_provider`. OAuth requires a non-empty `code` and preserves
/// optional `state`. Magic-link callbacks require a non-empty `token` and an
/// `email`, falling back to `identifier` only when email is null. A
/// [CallbackProvider] selects the custom branch; other types return
/// `unsupported_provider`. Query values use `toString()` and are not trimmed.
AuthCallbackRouteDecision resolveAuthCallbackRouteDecision({
  required String? providerId,
  required AuthProvider? provider,
  required Map<String, dynamic> query,
}) {
  if (providerId == null || providerId.isEmpty) {
    return const AuthCallbackRouteDecision.error('missing_provider');
  }

  if (provider == null) {
    return const AuthCallbackRouteDecision.error('unknown_provider');
  }

  if (provider is OAuthProvider) {
    final code = _stringValue(query['code']);
    if (code == null || code.isEmpty) {
      return const AuthCallbackRouteDecision.error('missing_code');
    }
    return AuthCallbackRouteDecision.oauth(
      code: code,
      state: _stringValue(query['state']),
    );
  }

  if (provider is AuthMagicLinkProvider) {
    final token = _stringValue(query['token']);
    final email =
        _stringValue(query['email']) ?? _stringValue(query['identifier']);
    if (token == null || token.isEmpty || email == null || email.isEmpty) {
      return const AuthCallbackRouteDecision.error('missing_token');
    }
    return AuthCallbackRouteDecision.email(token: token, email: email);
  }

  if (provider is CallbackProvider) {
    return const AuthCallbackRouteDecision.custom();
  }

  return const AuthCallbackRouteDecision.error('unsupported_provider');
}

String? _stringValue(Object? value) {
  if (value == null) {
    return null;
  }
  return value.toString();
}
