import 'providers.dart';

/// Sign-in route branch selected for a request.
enum AuthSignInRouteKind { oauth, email, credentials, error }

/// Concrete sign-in routing decision used by framework adapters.
class AuthSignInRouteDecision {
  const AuthSignInRouteDecision._({
    required this.kind,
    this.errorCode,
    required this.requiresCsrf,
    this.email,
  });

  const AuthSignInRouteDecision.oauth()
    : this._(kind: AuthSignInRouteKind.oauth, requiresCsrf: false);

  const AuthSignInRouteDecision.email(String email)
    : this._(kind: AuthSignInRouteKind.email, requiresCsrf: true, email: email);

  const AuthSignInRouteDecision.credentials()
    : this._(kind: AuthSignInRouteKind.credentials, requiresCsrf: true);

  const AuthSignInRouteDecision.error(
    String errorCode, {
    bool requiresCsrf = false,
  }) : this._(
         kind: AuthSignInRouteKind.error,
         errorCode: errorCode,
         requiresCsrf: requiresCsrf,
       );

  final AuthSignInRouteKind kind;
  final String? errorCode;
  final bool requiresCsrf;
  final String? email;
}

/// Register route branch selected for a request.
enum AuthRegisterRouteKind { credentials, error }

/// Concrete register routing decision used by framework adapters.
class AuthRegisterRouteDecision {
  const AuthRegisterRouteDecision._({
    required this.kind,
    this.errorCode,
    required this.requiresCsrf,
  });

  const AuthRegisterRouteDecision.credentials()
    : this._(kind: AuthRegisterRouteKind.credentials, requiresCsrf: true);

  const AuthRegisterRouteDecision.error(
    String errorCode, {
    bool requiresCsrf = false,
  }) : this._(
         kind: AuthRegisterRouteKind.error,
         errorCode: errorCode,
         requiresCsrf: requiresCsrf,
       );

  final AuthRegisterRouteKind kind;
  final String? errorCode;
  final bool requiresCsrf;
}

/// Callback route branch selected for a request.
enum AuthCallbackRouteKind { oauth, email, custom, error }

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

  const AuthCallbackRouteDecision.oauth({required String code, String? state})
    : this._(kind: AuthCallbackRouteKind.oauth, code: code, state: state);

  const AuthCallbackRouteDecision.email({
    required String token,
    required String email,
  }) : this._(kind: AuthCallbackRouteKind.email, token: token, email: email);

  const AuthCallbackRouteDecision.custom()
    : this._(kind: AuthCallbackRouteKind.custom);

  const AuthCallbackRouteDecision.error(String errorCode)
    : this._(kind: AuthCallbackRouteKind.error, errorCode: errorCode);

  final AuthCallbackRouteKind kind;
  final String? errorCode;
  final String? code;
  final String? state;
  final String? token;
  final String? email;
}

/// Resolves sign-in branching decisions used by auth route handlers.
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

  if (provider is EmailProvider) {
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

  if (provider is EmailProvider) {
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
