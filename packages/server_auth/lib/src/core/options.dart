import 'dart:convert';

import 'package:http/http.dart' as http;

import 'account_deletion.dart';
import 'account_policy.dart';
import 'authorization.dart';
import 'browser.dart';
import 'browser_validator.dart';
import 'callbacks.dart';
import 'email_change.dart';
import 'plugin.dart';
import 'jwt.dart';
import 'models.dart';
import 'password_hasher.dart';
import 'password_policy.dart';
import 'password_reset.dart';
import 'providers.dart';
import 'rate_limit.dart';
import 'runtime_posture.dart';
import 'store.dart';

/// Declares whether an auth store is durable across process restarts.
enum AuthStoreMode { durable, ephemeral }

/// Framework-agnostic auth runtime options.
///
/// Framework integrations map these options onto routing and session
/// infrastructure. Persistence is always supplied through [store].
class AuthOptions<TContext> {
  AuthOptions({
    required List<AuthProvider> providers,
    required this.store,
    AuthStoreMode storeMode = AuthStoreMode.durable,
    AuthRuntimeMode? runtimeMode,
    this.productionBoundary,
    this.plugins = const [],
    Iterable<String> historicalAuthenticationMethodNamespaces = const [],
    Iterable<String> historicalUserDataNamespaces = const [],
    this.sessionStrategy = AuthSessionStrategy.session,
    this.rateLimiter,
    AuthBrowserProtectionOptions? browserProtection,
    AuthCookiePolicy? cookiePolicy,
    AuthAccountPolicy? accountPolicy,
    this.passwordPolicy = const PasswordPolicy(),
    this.jwtOptions = const JwtSessionOptions(secret: ''),
    PasswordHasher? passwordHasher,
    this.sessionMaxAge,
    this.sessionUpdateAge,
    this.basePath = '/auth',
    this.csrfKey = '_auth.csrf',
    this.stateKey = '_auth.state',
    this.pkceKey = '_auth.pkce',
    this.nonceKey = '_auth.nonce',
    this.callbackKey = '_auth.callback',
    this.oauthChallengeTtl = const Duration(minutes: 10),
    this.passwordResetTtl = const Duration(minutes: 30),
    this.passwordResetSender,
    this.emailChangeTtl = const Duration(minutes: 30),
    this.emailChangeSender,
    this.accountDeletionTtl = const Duration(minutes: 30),
    this.accountDeletionSender,
    this.httpClient,
    this.enforceCsrf = true,
    this.requireVerifiedEmail = false,
    this.exposeJwtTokenInSessionResponse = false,
    this.rbac = const RbacOptions(),
    this.policies = const PolicyOptions(),
    AuthCallbacks<TContext>? callbacks,
  }) : storeMode = storeMode,
       runtimeMode = runtimeMode ?? _defaultRuntimeMode(storeMode),
       browserProtection =
           browserProtection ??
           _defaultBrowserProtection(
             storeMode,
             runtimeMode,
             productionBoundary,
           ),
       cookiePolicy =
           cookiePolicy ?? _defaultCookiePolicy(storeMode, runtimeMode),
       accountPolicy =
           accountPolicy ?? _defaultAccountPolicy(storeMode, runtimeMode),
       providers = List<AuthProvider>.unmodifiable(providers),
       historicalAuthenticationMethodNamespaces =
           _normalizeHistoricalAuthenticationMethodNamespaces(
             historicalAuthenticationMethodNamespaces,
           ),
       historicalUserDataNamespaces = _normalizeHistoricalUserDataNamespaces(
         historicalUserDataNamespaces,
       ),
       passwordHasher = passwordHasher ?? Argon2idPasswordHasher(),
       callbacks = callbacks ?? AuthCallbacks<TContext>() {
    validateAuthProviderConfiguration(this.providers);
    if (store is CallbackAuthStore) {
      throw ArgumentError(
        'CallbackAuthStore is a test utility and cannot back AuthOptions; '
        'provide a durable AuthStore implementation.',
      );
    }
    if (oauthChallengeTtl <= Duration.zero) {
      throw ArgumentError.value(
        oauthChallengeTtl,
        'oauthChallengeTtl',
        'must be greater than zero',
      );
    }
    if (passwordResetTtl <= Duration.zero) {
      throw ArgumentError.value(
        passwordResetTtl,
        'passwordResetTtl',
        'must be greater than zero',
      );
    }
    if (emailChangeTtl <= Duration.zero) {
      throw ArgumentError.value(
        emailChangeTtl,
        'emailChangeTtl',
        'must be greater than zero',
      );
    }
    if (accountDeletionTtl <= Duration.zero) {
      throw ArgumentError.value(
        accountDeletionTtl,
        'accountDeletionTtl',
        'must be greater than zero',
      );
    }
    final isEphemeralStore = store is InMemoryAuthStore;
    if (isEphemeralStore && storeMode != AuthStoreMode.ephemeral) {
      throw ArgumentError(
        'InMemoryAuthStore requires AuthStoreMode.ephemeral; '
        'use a durable AuthStore for production.',
      );
    }
    if (!isEphemeralStore && storeMode == AuthStoreMode.ephemeral) {
      throw ArgumentError(
        'AuthStoreMode.ephemeral requires InMemoryAuthStore.',
      );
    }
    _validateRuntimePosture();
  }

  /// List of configured auth providers.
  final List<AuthProvider> providers;

  /// Typed plugin modules composed into the auth runtime.
  final List<AuthServerPlugin<TContext>> plugins;

  /// Namespaces from previously deployed authentication plugins whose stores
  /// are not currently composed. Missing contributors make destructive
  /// authentication-method mutations fail closed.
  final List<String> historicalAuthenticationMethodNamespaces;

  /// Namespaces from previously deployed plugins whose user-owned records
  /// are not currently composed. Missing contributors make hard deletion
  /// fail closed when the coordinator supports historical topology checks.
  final List<String> historicalUserDataNamespaces;

  /// Typed persistence boundary used by every auth flow.
  final AuthStore store;

  /// Declares whether [store] is durable or intentionally in-memory.
  final AuthStoreMode storeMode;

  /// Whether this runtime must satisfy production guarantees or was
  /// deliberately relaxed for local development.
  ///
  /// [AuthStoreMode.ephemeral] derives [AuthRuntimeMode.localDevelopment].
  /// Durable options derive [AuthRuntimeMode.production], which requires an
  /// explicit [productionBoundary].
  final AuthRuntimeMode runtimeMode;

  /// Exact browser-origin and proxy trust decision for production boot.
  ///
  /// This is required when [runtimeMode] is [AuthRuntimeMode.production] and
  /// rejected for local-development options so the two postures cannot be
  /// accidentally mixed.
  final AuthProductionBoundary? productionBoundary;

  /// Session storage strategy.
  final AuthSessionStrategy sessionStrategy;

  /// Optional policy for throttling externally reachable auth operations.
  ///
  /// Framework adapters must invoke this policy at their auth boundaries. The
  /// Routed adapter does so for all built-in auth routes.
  final AuthRateLimiter<TContext>? rateLimiter;

  /// Browser origin and Fetch Metadata checks for state-changing auth routes.
  final AuthBrowserProtectionOptions browserProtection;

  /// Cookie security policy for auth cookies.
  final AuthCookiePolicy cookiePolicy;

  /// Account state and authentication policy.
  final AuthAccountPolicy accountPolicy;

  /// Registration and verifier-input limits for built-in credentials.
  final PasswordPolicy passwordPolicy;

  /// JWT configuration when using [AuthSessionStrategy.jwt].
  final JwtSessionOptions jwtOptions;

  /// Password hashing policy used by the built-in credentials flow.
  final PasswordHasher passwordHasher;

  /// Maximum age for auth sessions.
  final Duration? sessionMaxAge;

  /// Duration before session is refreshed.
  final Duration? sessionUpdateAge;

  /// Base path for auth routes.
  final String basePath;

  /// Session key for CSRF tokens.
  final String csrfKey;

  /// Session key for OAuth state.
  final String stateKey;

  /// Session key for PKCE verifier.
  final String pkceKey;

  /// Session key for provider OIDC nonce values.
  final String nonceKey;

  /// Session key used to store callback URLs.
  final String callbackKey;

  /// Maximum age of a persisted OAuth authorization challenge.
  final Duration oauthChallengeTtl;

  /// Maximum age of a persisted password-reset token.
  final Duration passwordResetTtl;

  /// Application-owned delivery callback for password-reset messages.
  ///
  /// Routed registers its built-in password-reset routes when this callback
  /// is configured. Password resets also rotate the user's JWT version.
  final AuthPasswordResetSender<TContext>? passwordResetSender;

  /// Maximum age of a pending email-change token.
  final Duration emailChangeTtl;

  /// Application-owned delivery callback for email-change confirmations.
  final AuthEmailChangeSender<TContext>? emailChangeSender;

  /// Maximum age of a pending account-deletion confirmation.
  final Duration accountDeletionTtl;

  /// Application-owned delivery callback for account-deletion confirmations.
  final AuthAccountDeletionSender<TContext>? accountDeletionSender;

  /// HTTP client used for OAuth calls.
  final http.Client? httpClient;

  /// Whether to enforce CSRF checks on sign-in/sign-out.
  final bool enforceCsrf;

  /// Whether every authentication boundary must have a verified email.
  ///
  /// Provider profile claims are accepted only when they use the explicit
  /// boolean verified flags understood by [authUserEmailIsVerified]. Email
  /// magic-link completion marks the local user verified before a session is
  /// issued.
  final bool requireVerifiedEmail;

  /// Whether session endpoint payloads may include the raw JWT bearer token.
  ///
  /// Keep this disabled when the JWT is delivered through an HTTP-only cookie.
  final bool exposeJwtTokenInSessionResponse;

  /// Role-based access control mappings.
  final RbacOptions rbac;

  /// Policy bindings for resource-level authorization.
  final PolicyOptions policies;

  /// Auth callback hooks.
  final AuthCallbacks<TContext> callbacks;

  /// Throws when this configuration intentionally selects ephemeral storage.
  ///
  /// Framework adapters should call this during production boot. The default
  /// [AuthStoreMode.durable] also makes an unannotated [InMemoryAuthStore]
  /// fail at option construction time.
  void requireDurableStore() {
    if (storeMode == AuthStoreMode.ephemeral) {
      throw StateError(
        'Ephemeral auth storage is not allowed for production boot.',
      );
    }
  }

  /// Revalidates every guarantee required for production boot.
  void requireProductionBoot() {
    if (runtimeMode != AuthRuntimeMode.production) {
      throw StateError(
        'Local-development auth options cannot boot through a production '
        'provider. Use AuthDeploymentPresets.localDevelopment explicitly.',
      );
    }
    _validateRuntimePosture();
  }

  /// Ensures a framework adapter and its options use the same posture.
  void requireRuntimeMode(AuthRuntimeMode expected) {
    if (runtimeMode != expected) {
      throw StateError(
        'Auth runtime posture mismatch: the provider requires '
        '${expected.name}, but AuthOptions uses ${runtimeMode.name}.',
      );
    }
    if (expected == AuthRuntimeMode.production) requireProductionBoot();
  }

  void _validateRuntimePosture() {
    if (runtimeMode == AuthRuntimeMode.localDevelopment) {
      if (productionBoundary != null) {
        throw ArgumentError.value(
          productionBoundary,
          'productionBoundary',
          'must be omitted for local-development auth options',
        );
      }
      return;
    }

    requireDurableStore();
    final boundary = productionBoundary;
    if (boundary == null) {
      throw ArgumentError.notNull('productionBoundary');
    }
    _validateProductionBrowserPolicy(browserProtection, boundary);
    if (!cookiePolicy.httpOnly || !cookiePolicy.secure) {
      throw ArgumentError.value(
        cookiePolicy,
        'cookiePolicy',
        'production cookies must be Secure and HttpOnly',
      );
    }
    if (rateLimiter == null) {
      throw ArgumentError.notNull('rateLimiter');
    }
    for (final plugin
        in plugins.whereType<AuthProductionPostureContributor>()) {
      plugin.validateProductionPosture();
    }
    if (sessionStrategy == AuthSessionStrategy.jwt) {
      _validateProductionJwt(jwtOptions);
    }
  }

  AuthOptions<TContext> copyWith({
    List<AuthProvider>? providers,
    AuthStore? store,
    AuthStoreMode? storeMode,
    AuthRuntimeMode? runtimeMode,
    AuthProductionBoundary? productionBoundary,
    List<AuthServerPlugin<TContext>>? plugins,
    Iterable<String>? historicalAuthenticationMethodNamespaces,
    Iterable<String>? historicalUserDataNamespaces,
    AuthSessionStrategy? sessionStrategy,
    AuthRateLimiter<TContext>? rateLimiter,
    AuthBrowserProtectionOptions? browserProtection,
    AuthCookiePolicy? cookiePolicy,
    AuthAccountPolicy? accountPolicy,
    PasswordPolicy? passwordPolicy,
    JwtSessionOptions? jwtOptions,
    PasswordHasher? passwordHasher,
    Duration? sessionMaxAge,
    Duration? sessionUpdateAge,
    String? basePath,
    String? csrfKey,
    String? stateKey,
    String? pkceKey,
    String? nonceKey,
    String? callbackKey,
    Duration? oauthChallengeTtl,
    Duration? passwordResetTtl,
    AuthPasswordResetSender<TContext>? passwordResetSender,
    Duration? emailChangeTtl,
    AuthEmailChangeSender<TContext>? emailChangeSender,
    Duration? accountDeletionTtl,
    AuthAccountDeletionSender<TContext>? accountDeletionSender,
    http.Client? httpClient,
    bool? enforceCsrf,
    bool? requireVerifiedEmail,
    bool? exposeJwtTokenInSessionResponse,
    RbacOptions? rbac,
    PolicyOptions? policies,
    AuthCallbacks<TContext>? callbacks,
  }) {
    return AuthOptions<TContext>(
      providers: providers ?? this.providers,
      store: store ?? this.store,
      storeMode: storeMode ?? this.storeMode,
      runtimeMode: runtimeMode ?? this.runtimeMode,
      productionBoundary: productionBoundary ?? this.productionBoundary,
      plugins: plugins ?? this.plugins,
      historicalAuthenticationMethodNamespaces:
          historicalAuthenticationMethodNamespaces ??
          this.historicalAuthenticationMethodNamespaces,
      historicalUserDataNamespaces:
          historicalUserDataNamespaces ?? this.historicalUserDataNamespaces,
      sessionStrategy: sessionStrategy ?? this.sessionStrategy,
      rateLimiter: rateLimiter ?? this.rateLimiter,
      browserProtection: browserProtection ?? this.browserProtection,
      cookiePolicy: cookiePolicy ?? this.cookiePolicy,
      accountPolicy: accountPolicy ?? this.accountPolicy,
      passwordPolicy: passwordPolicy ?? this.passwordPolicy,
      jwtOptions: jwtOptions ?? this.jwtOptions,
      passwordHasher: passwordHasher ?? this.passwordHasher,
      sessionMaxAge: sessionMaxAge ?? this.sessionMaxAge,
      sessionUpdateAge: sessionUpdateAge ?? this.sessionUpdateAge,
      basePath: basePath ?? this.basePath,
      csrfKey: csrfKey ?? this.csrfKey,
      stateKey: stateKey ?? this.stateKey,
      pkceKey: pkceKey ?? this.pkceKey,
      nonceKey: nonceKey ?? this.nonceKey,
      callbackKey: callbackKey ?? this.callbackKey,
      oauthChallengeTtl: oauthChallengeTtl ?? this.oauthChallengeTtl,
      passwordResetTtl: passwordResetTtl ?? this.passwordResetTtl,
      passwordResetSender: passwordResetSender ?? this.passwordResetSender,
      emailChangeTtl: emailChangeTtl ?? this.emailChangeTtl,
      emailChangeSender: emailChangeSender ?? this.emailChangeSender,
      accountDeletionTtl: accountDeletionTtl ?? this.accountDeletionTtl,
      accountDeletionSender:
          accountDeletionSender ?? this.accountDeletionSender,
      httpClient: httpClient ?? this.httpClient,
      enforceCsrf: enforceCsrf ?? this.enforceCsrf,
      requireVerifiedEmail: requireVerifiedEmail ?? this.requireVerifiedEmail,
      exposeJwtTokenInSessionResponse:
          exposeJwtTokenInSessionResponse ??
          this.exposeJwtTokenInSessionResponse,
      rbac: rbac ?? this.rbac,
      policies: policies ?? this.policies,
      callbacks: callbacks ?? this.callbacks,
    );
  }
}

AuthRuntimeMode _defaultRuntimeMode(AuthStoreMode storeMode) =>
    storeMode == AuthStoreMode.ephemeral
    ? AuthRuntimeMode.localDevelopment
    : AuthRuntimeMode.production;

List<String> _normalizeHistoricalAuthenticationMethodNamespaces(
  Iterable<String> values,
) {
  final namespaces = <String>{};
  for (final value in values) {
    final normalized = value.trim();
    if (value.isEmpty ||
        value != normalized ||
        value.length > 64 ||
        value.contains(RegExp(r'[\u0000-\u001f\u007f]')) ||
        !namespaces.add(value)) {
      throw ArgumentError.value(
        values,
        'historicalAuthenticationMethodNamespaces',
        'must contain unique, bounded, safe namespace values',
      );
    }
  }
  return List<String>.unmodifiable(namespaces);
}

List<String> _normalizeHistoricalUserDataNamespaces(Iterable<String> values) {
  final namespaces = <String>{};
  for (final value in values) {
    final normalized = value.trim().toLowerCase();
    if (normalized != value ||
        normalized.isEmpty ||
        normalized.length > 64 ||
        normalized.contains(RegExp(r'[\u0000-\u001f\u007f]')) ||
        !namespaces.add(normalized)) {
      throw ArgumentError.value(
        values,
        'historicalUserDataNamespaces',
        'must contain unique, bounded, canonical namespace values',
      );
    }
  }
  return List<String>.unmodifiable(namespaces);
}

AuthRuntimeMode _resolvedRuntimeMode(
  AuthStoreMode storeMode,
  AuthRuntimeMode? runtimeMode,
) => runtimeMode ?? _defaultRuntimeMode(storeMode);

AuthBrowserProtectionOptions _defaultBrowserProtection(
  AuthStoreMode storeMode,
  AuthRuntimeMode? runtimeMode,
  AuthProductionBoundary? boundary,
) {
  final resolved = _resolvedRuntimeMode(storeMode, runtimeMode);
  if (resolved == AuthRuntimeMode.localDevelopment) {
    return AuthBrowserProtectionOptions.localDevelopment;
  }
  return AuthBrowserProtectionOptions.production(
    trustedOrigins: boundary?.trustedOrigins ?? const <String>[],
  );
}

AuthCookiePolicy _defaultCookiePolicy(
  AuthStoreMode storeMode,
  AuthRuntimeMode? runtimeMode,
) =>
    _resolvedRuntimeMode(storeMode, runtimeMode) ==
        AuthRuntimeMode.localDevelopment
    ? AuthCookiePolicy.development
    : AuthCookiePolicy.production;

AuthAccountPolicy _defaultAccountPolicy(
  AuthStoreMode storeMode,
  AuthRuntimeMode? runtimeMode,
) =>
    _resolvedRuntimeMode(storeMode, runtimeMode) ==
        AuthRuntimeMode.localDevelopment
    ? AuthAccountPolicy.development
    : AuthAccountPolicy.production;

void _validateProductionBrowserPolicy(
  AuthBrowserProtectionOptions policy,
  AuthProductionBoundary boundary,
) {
  if (!policy.enabled ||
      !policy.requireOrigin ||
      !policy.enforceFetchMetadata ||
      !policy.enforceReferrer ||
      !policy.requireContentType) {
    throw ArgumentError.value(
      policy,
      'browserProtection',
      'production browser protection must require Origin, Fetch Metadata, '
          'Referer fallback, and Content-Type checks',
    );
  }
  final configuredOrigins = <String>{
    ...policy.allowedOrigins,
    ...policy.trustedOrigins,
  };
  final boundaryOrigins = boundary.trustedOrigins.toSet();
  if (configuredOrigins.length != boundaryOrigins.length ||
      !configuredOrigins.containsAll(boundaryOrigins)) {
    throw ArgumentError.value(
      configuredOrigins,
      'browserProtection',
      'allowed and trusted origins must exactly match the production boundary',
    );
  }
  for (final value in configuredOrigins) {
    final origin = Uri.tryParse(value);
    if (origin == null ||
        normalizeAuthOrigin(origin, requireHttps: true) != value) {
      throw ArgumentError.value(
        value,
        'browserProtection',
        'production origins must be canonical HTTPS origins',
      );
    }
  }
}

void _validateProductionJwt(JwtSessionOptions options) {
  final algorithm = options.algorithm.trim().toUpperCase();
  final minimumBytes = switch (algorithm) {
    'HS256' => 32,
    'HS384' => 48,
    'HS512' => 64,
    _ => throw ArgumentError.value(
      options.algorithm,
      'jwtOptions.algorithm',
      'production JWT sessions support HS256, HS384, or HS512',
    ),
  };
  if (utf8.encode(options.secret).length < minimumBytes) {
    throw ArgumentError.value(
      '<redacted>',
      'jwtOptions.secret',
      'must contain at least $minimumBytes UTF-8 bytes for $algorithm',
    );
  }
  if (!options.secure) {
    throw ArgumentError.value(
      options.secure,
      'jwtOptions.secure',
      'production JWT cookies must be Secure',
    );
  }
}

/// Resolves final auth runtime options by combining base [options] with
/// framework overrides and explicitly supplied provider additions.
///
/// This helper keeps option merge behavior consistent across framework
/// integrations (for example Routed and Shelf adapters).
AuthOptions<TContext> resolveAuthOptions<TContext>({
  required AuthOptions<TContext> options,
  Iterable<AuthProvider> configuredProviders = const <AuthProvider>[],
  AuthStore? store,
  http.Client? httpClient,
  AuthSessionStrategy? sessionStrategy,
  Duration? sessionMaxAge,
  Duration? sessionUpdateAge,
}) {
  final mergedProviders = mergeAuthProvidersById(
    options.providers,
    configuredProviders,
  );
  return options.copyWith(
    providers: mergedProviders,
    store: store ?? options.store,
    storeMode: store == null
        ? options.storeMode
        : store is InMemoryAuthStore
        ? AuthStoreMode.ephemeral
        : AuthStoreMode.durable,
    httpClient: options.httpClient ?? httpClient,
    sessionStrategy: sessionStrategy ?? options.sessionStrategy,
    sessionMaxAge: options.sessionMaxAge ?? sessionMaxAge,
    sessionUpdateAge: options.sessionUpdateAge ?? sessionUpdateAge,
  );
}
