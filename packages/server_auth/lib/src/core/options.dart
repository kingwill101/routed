import 'package:http/http.dart' as http;

import 'authorization.dart';
import 'browser.dart';
import 'callbacks.dart';
import 'feature.dart';
import 'jwt.dart';
import 'models.dart';
import 'password_hasher.dart';
import 'password_policy.dart';
import 'password_reset.dart';
import 'providers.dart';
import 'rate_limit.dart';
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
    this.storeMode = AuthStoreMode.durable,
    this.features = const [],
    this.sessionStrategy = AuthSessionStrategy.session,
    this.rateLimiter,
    this.browserProtection = const AuthBrowserProtectionOptions(),
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
    this.httpClient,
    this.enforceCsrf = true,
    this.exposeJwtTokenInSessionResponse = false,
    this.rbac = const RbacOptions(),
    this.policies = const PolicyOptions(),
    AuthCallbacks<TContext>? callbacks,
  }) : providers = List<AuthProvider>.unmodifiable(providers),
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
  }

  /// List of configured auth providers.
  final List<AuthProvider> providers;

  /// Typed feature modules composed into the auth runtime.
  final List<AuthFeature<TContext>> features;

  /// Typed persistence boundary used by every auth flow.
  final AuthStore store;

  /// Declares whether [store] is durable or intentionally in-memory.
  final AuthStoreMode storeMode;

  /// Session storage strategy.
  final AuthSessionStrategy sessionStrategy;

  /// Optional policy for throttling externally reachable auth operations.
  ///
  /// Framework adapters must invoke this policy at their auth boundaries. The
  /// Routed adapter does so for all built-in auth routes.
  final AuthRateLimiter<TContext>? rateLimiter;

  /// Browser origin and Fetch Metadata checks for state-changing auth routes.
  final AuthBrowserProtectionOptions browserProtection;

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

  /// HTTP client used for OAuth calls.
  final http.Client? httpClient;

  /// Whether to enforce CSRF checks on sign-in/sign-out.
  final bool enforceCsrf;

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

  AuthOptions<TContext> copyWith({
    List<AuthProvider>? providers,
    AuthStore? store,
    AuthStoreMode? storeMode,
    List<AuthFeature<TContext>>? features,
    AuthSessionStrategy? sessionStrategy,
    AuthRateLimiter<TContext>? rateLimiter,
    AuthBrowserProtectionOptions? browserProtection,
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
    http.Client? httpClient,
    bool? enforceCsrf,
    bool? exposeJwtTokenInSessionResponse,
    RbacOptions? rbac,
    PolicyOptions? policies,
    AuthCallbacks<TContext>? callbacks,
  }) {
    return AuthOptions<TContext>(
      providers: providers ?? this.providers,
      store: store ?? this.store,
      storeMode: storeMode ?? this.storeMode,
      features: features ?? this.features,
      sessionStrategy: sessionStrategy ?? this.sessionStrategy,
      rateLimiter: rateLimiter ?? this.rateLimiter,
      browserProtection: browserProtection ?? this.browserProtection,
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
      httpClient: httpClient ?? this.httpClient,
      enforceCsrf: enforceCsrf ?? this.enforceCsrf,
      exposeJwtTokenInSessionResponse:
          exposeJwtTokenInSessionResponse ??
          this.exposeJwtTokenInSessionResponse,
      rbac: rbac ?? this.rbac,
      policies: policies ?? this.policies,
      callbacks: callbacks ?? this.callbacks,
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
