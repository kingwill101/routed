import 'dart:async';

import 'exceptions.dart';
import 'models.dart';
import 'password_policy.dart';
import 'plugin.dart';

/// Stable ID for the opt-in breached-password policy plugin.
const authBreachedPasswordPluginId = 'breached_password';

/// Generic public error used for a breached password and for every lookup
/// failure. This prevents provider health and vendor-specific details from
/// becoming an authentication oracle.
const authBreachedPasswordRejectedErrorCode = 'password_rejected';

/// Typed limits and operation selection for breached-password checks.
final class AuthBreachedPasswordPluginConfig {
  const AuthBreachedPasswordPluginConfig({
    this.providerTimeout = const Duration(seconds: 3),
    this.maxPasswordLength = 1024,
    this.checkRegistration = true,
    this.checkPasswordReset = true,
    this.checkPasswordChange = true,
  }) : assert(maxPasswordLength > 0 && maxPasswordLength <= 4096);

  /// Maximum time allowed for one application-owned lookup.
  final Duration providerTimeout;

  /// Maximum password length passed to the lookup service.
  final int maxPasswordLength;

  /// Whether registration passwords are checked.
  final bool checkRegistration;

  /// Whether password-reset replacement passwords are checked.
  final bool checkPasswordReset;

  /// Whether authenticated password changes are checked.
  final bool checkPasswordChange;
}

/// Typed input passed to an application-owned breached-password lookup.
///
/// [password] is a secret. The lookup implementation must use it only for its
/// private check and must never log, persist, return, or include it in an
/// exception or diagnostic value.
final class AuthBreachedPasswordCheckRequest<TContext> {
  const AuthBreachedPasswordCheckRequest({
    required this.context,
    required this.password,
    required this.operation,
    this.user,
  });

  final TContext context;
  final String password;
  final AuthPasswordPolicyOperation operation;
  final AuthUser? user;
}

/// Typed result returned by an application-owned breached-password lookup.
final class AuthBreachedPasswordCheckResult {
  const AuthBreachedPasswordCheckResult({required this.breached});

  const AuthBreachedPasswordCheckResult.allowed() : breached = false;

  const AuthBreachedPasswordCheckResult.breached() : breached = true;

  final bool breached;
}

/// Application-owned boundary for a breached-password lookup.
///
/// An implementation may use a local corpus, a k-anonymous remote query, or
/// another privacy-preserving service. The auth package does not select a
/// vendor and never receives a vendor-specific response shape.
abstract interface class AuthBreachedPasswordLookup<TContext> {
  FutureOr<AuthBreachedPasswordCheckResult> check(
    AuthBreachedPasswordCheckRequest<TContext> request,
  );
}

/// Opt-in protection for newly created or replacement passwords.
final class BreachedPasswordPlugin<TContext>
    implements
        AuthServerPlugin<TContext>,
        AuthPasswordPolicyContributor<TContext> {
  BreachedPasswordPlugin({
    required this.lookup,
    this.config = const AuthBreachedPasswordPluginConfig(),
  }) {
    _validateConfig(config);
  }

  final AuthBreachedPasswordLookup<TContext> lookup;
  final AuthBreachedPasswordPluginConfig config;
  late PasswordPolicy _passwordPolicy;
  bool _configured = false;

  @override
  String get id => authBreachedPasswordPluginId;

  @override
  void configure(AuthServerPluginContext<TContext> context) {
    _passwordPolicy = context.passwordPolicy;
    _configured = true;
  }

  @override
  Future<void> enforcePasswordPolicy(
    AuthPasswordPolicyRequest<TContext> request,
  ) async {
    _ensureConfigured();
    if (!_isEnabledFor(request.operation)) return;

    // Preserve the built-in password-policy errors and avoid sending malformed
    // passwords to the application-owned lookup.
    final builtInError = _passwordPolicy.validateRegistration(request.password);
    if (builtInError != null) {
      throw AuthFlowException(builtInError);
    }
    if (request.password.length > config.maxPasswordLength) {
      throw AuthFlowException(authBreachedPasswordRejectedErrorCode);
    }

    try {
      final result = await Future<AuthBreachedPasswordCheckResult>.sync(
        () => lookup.check(
          AuthBreachedPasswordCheckRequest<TContext>(
            context: request.context,
            password: request.password,
            operation: request.operation,
            user: request.user,
          ),
        ),
      ).timeout(config.providerTimeout);
      if (result.breached) {
        throw AuthFlowException(authBreachedPasswordRejectedErrorCode);
      }
    } catch (_) {
      throw AuthFlowException(authBreachedPasswordRejectedErrorCode);
    }
  }

  bool _isEnabledFor(AuthPasswordPolicyOperation operation) {
    switch (operation) {
      case AuthPasswordPolicyOperation.registration:
        return config.checkRegistration;
      case AuthPasswordPolicyOperation.passwordReset:
        return config.checkPasswordReset;
      case AuthPasswordPolicyOperation.passwordChange:
        return config.checkPasswordChange;
    }
  }

  void _ensureConfigured() {
    if (!_configured) {
      throw StateError(
        'BreachedPasswordPlugin must be configured by AuthRuntime.',
      );
    }
  }

  static void _validateConfig(AuthBreachedPasswordPluginConfig config) {
    if (config.providerTimeout <= Duration.zero ||
        config.providerTimeout > const Duration(seconds: 30)) {
      throw ArgumentError.value(
        config.providerTimeout,
        'config.providerTimeout',
        'must be greater than zero and at most 30 seconds',
      );
    }
    if (config.maxPasswordLength <= 0 || config.maxPasswordLength > 4096) {
      throw ArgumentError.value(
        config.maxPasswordLength,
        'config.maxPasswordLength',
        'must be between 1 and 4096',
      );
    }
  }
}
