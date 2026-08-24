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
  /// Creates breached-password protection settings.
  ///
  /// Defaults enable checks for registration, reset, and change operations,
  /// allow 1,024-character passwords, and give the lookup three seconds. The
  /// [maxPasswordLength] assertion constrains it to 1..4,096; the plugin also
  /// validates [providerTimeout] as greater than zero and at most 30 seconds.
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
  /// Creates a lookup request containing the password secret.
  ///
  /// [context], [operation], and optional [user] identify the flow. The
  /// [password] must be used only for the private check and must never be
  /// logged, persisted, returned, or included in errors or diagnostics.
  const AuthBreachedPasswordCheckRequest({
    required this.context,
    required this.password,
    required this.operation,
    this.user,
  });

  /// Application context associated with the password operation.
  final TContext context;

  /// Password secret to check; it must not be logged or persisted.
  final String password;

  /// Password operation that triggered the lookup.
  final AuthPasswordPolicyOperation operation;

  /// Existing user for password changes or resets, when available.
  final AuthUser? user;
}

/// Typed result returned by an application-owned breached-password lookup.
final class AuthBreachedPasswordCheckResult {
  /// Creates a result with the explicit [breached] status.
  const AuthBreachedPasswordCheckResult({required this.breached});

  /// Creates an allowed result.
  const AuthBreachedPasswordCheckResult.allowed() : breached = false;

  /// Creates a result rejecting a password found in the breach corpus.
  const AuthBreachedPasswordCheckResult.breached() : breached = true;

  /// Whether the checked password was found to be breached.
  final bool breached;
}

/// Application-owned boundary for a breached-password lookup.
///
/// An implementation may use a local corpus, a k-anonymous remote query, or
/// another privacy-preserving service. The auth package does not select a
/// vendor and never receives a vendor-specific response shape.
abstract interface class AuthBreachedPasswordLookup<TContext> {
  /// Checks [request] synchronously or asynchronously and returns a typed result.
  ///
  /// The plugin treats thrown exceptions and timeouts as rejection.
  FutureOr<AuthBreachedPasswordCheckResult> check(
    AuthBreachedPasswordCheckRequest<TContext> request,
  );
}

/// Opt-in protection for newly created or replacement passwords.
final class BreachedPasswordPlugin<TContext>
    implements
        AuthServerPlugin<TContext>,
        AuthPasswordPolicyContributor<TContext> {
  /// Creates opt-in breached-password enforcement using [lookup].
  ///
  /// [config] controls operations, timeout, and input length. The plugin must
  /// be configured by [AuthRuntime] before enforcement begins.
  BreachedPasswordPlugin({
    required this.lookup,
    this.config = const AuthBreachedPasswordPluginConfig(),
  }) {
    _validateConfig(config);
  }

  /// Application-owned breached-password lookup boundary.
  final AuthBreachedPasswordLookup<TContext> lookup;

  /// Enforcement limits and operation selection.
  final AuthBreachedPasswordPluginConfig config;
  late PasswordPolicy _passwordPolicy;
  bool _configured = false;

  /// Stable plugin identifier used in runtime configuration.
  @override
  String get id => authBreachedPasswordPluginId;

  /// Declares that this plugin contributes no persisted data contract.
  @override
  AuthServerPluginDataContract get dataContract =>
      const AuthServerPluginDataContract.none();

  /// Captures the runtime password policy before enforcement.
  @override
  void configure(AuthServerPluginContext<TContext> context) {
    _passwordPolicy = context.passwordPolicy;
    _configured = true;
  }

  /// Rejects enabled operations when the password is breached or lookup fails.
  ///
  /// Built-in password validation runs before lookup for registration, reset,
  /// and change operations. Overly long passwords are rejected without lookup.
  /// Breaches, exceptions, and timeouts all use
  /// [authBreachedPasswordRejectedErrorCode] and never expose the password.
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
