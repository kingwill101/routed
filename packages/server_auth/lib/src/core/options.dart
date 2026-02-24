import 'package:http/http.dart' as http;

import 'adapter.dart';
import 'authorization.dart';
import 'callbacks.dart';
import 'jwt.dart';
import 'models.dart';
import 'providers.dart';
import 'verification_token_store.dart';

/// Framework-agnostic auth runtime options.
///
/// Adapters should map these options onto framework-specific routing and
/// session integration.
class AuthOptions<TContext> {
  AuthOptions({
    required this.providers,
    this.adapter = const AuthAdapter(),
    this.sessionStrategy = AuthSessionStrategy.session,
    this.jwtOptions = const JwtSessionOptions(secret: ''),
    this.sessionMaxAge,
    this.sessionUpdateAge,
    this.basePath = '/auth',
    this.csrfKey = '_auth.csrf',
    this.stateKey = '_auth.state',
    this.pkceKey = '_auth.pkce',
    this.callbackKey = '_auth.callback',
    this.httpClient,
    this.tokenStore,
    this.enforceCsrf = true,
    this.rbac = const RbacOptions(),
    this.policies = const PolicyOptions(),
    AuthCallbacks<TContext>? callbacks,
  }) : callbacks = callbacks ?? AuthCallbacks<TContext>();

  /// List of configured auth providers.
  final List<AuthProvider> providers;

  /// Adapter used for persistence (users, accounts, sessions).
  final AuthAdapter adapter;

  /// Session storage strategy.
  final AuthSessionStrategy sessionStrategy;

  /// JWT configuration when using [AuthSessionStrategy.jwt].
  final JwtSessionOptions jwtOptions;

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

  /// Session key used to store callback URLs.
  final String callbackKey;

  /// HTTP client used for OAuth calls.
  final http.Client? httpClient;

  /// Token store used for email verification tokens.
  final AuthVerificationTokenStore? tokenStore;

  /// Whether to enforce CSRF checks on sign-in/sign-out.
  final bool enforceCsrf;

  /// Role-based access control mappings.
  final RbacOptions rbac;

  /// Policy bindings for resource-level authorization.
  final PolicyOptions policies;

  /// Auth callback hooks.
  final AuthCallbacks<TContext> callbacks;

  AuthOptions<TContext> copyWith({
    List<AuthProvider>? providers,
    AuthAdapter? adapter,
    AuthSessionStrategy? sessionStrategy,
    JwtSessionOptions? jwtOptions,
    Duration? sessionMaxAge,
    Duration? sessionUpdateAge,
    String? basePath,
    String? csrfKey,
    String? stateKey,
    String? pkceKey,
    String? callbackKey,
    http.Client? httpClient,
    AuthVerificationTokenStore? tokenStore,
    bool? enforceCsrf,
    RbacOptions? rbac,
    PolicyOptions? policies,
    AuthCallbacks<TContext>? callbacks,
  }) {
    return AuthOptions<TContext>(
      providers: providers ?? this.providers,
      adapter: adapter ?? this.adapter,
      sessionStrategy: sessionStrategy ?? this.sessionStrategy,
      jwtOptions: jwtOptions ?? this.jwtOptions,
      sessionMaxAge: sessionMaxAge ?? this.sessionMaxAge,
      sessionUpdateAge: sessionUpdateAge ?? this.sessionUpdateAge,
      basePath: basePath ?? this.basePath,
      csrfKey: csrfKey ?? this.csrfKey,
      stateKey: stateKey ?? this.stateKey,
      pkceKey: pkceKey ?? this.pkceKey,
      callbackKey: callbackKey ?? this.callbackKey,
      httpClient: httpClient ?? this.httpClient,
      tokenStore: tokenStore ?? this.tokenStore,
      enforceCsrf: enforceCsrf ?? this.enforceCsrf,
      rbac: rbac ?? this.rbac,
      policies: policies ?? this.policies,
      callbacks: callbacks ?? this.callbacks,
    );
  }
}
