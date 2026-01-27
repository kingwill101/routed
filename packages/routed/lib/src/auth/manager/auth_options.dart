import 'package:http/http.dart' as http;
import 'package:routed/src/auth/adapter.dart';
import 'package:routed/src/auth/hooks.dart';
import 'package:routed/src/auth/models.dart';
import 'package:routed/src/auth/providers.dart';
import 'package:routed/src/auth/jwt.dart';
import 'package:routed/src/auth/policies.dart';
import 'package:routed/src/auth/rbac.dart';
import 'package:routed/src/auth/session_auth.dart';

import 'verification_token_store.dart';

/// {@template routed_auth_manager}
/// High-level auth coordinator for routed.
///
/// ## Basic usage
/// ```dart
/// final engine = await Engine.create(providers: Engine.defaultProviders);
/// engine.container.instance<AuthOptions>(
///   AuthOptions(
///     providers: [
///       CredentialsProvider(
///         authorize: (ctx, provider, credentials) async {
///           return AuthUser(id: 'user-1', email: credentials.email);
///         },
///       ),
///     ],
///     sessionStrategy: AuthSessionStrategy.session,
///   ),
/// );
///
/// // AuthServiceProvider will bind AuthManager and register AuthRoutes.
/// await engine.serve(host: '127.0.0.1', port: 8080);
/// ```
///
/// ## Session strategies
/// - `session`: Uses the server session store via `SessionAuthService`.
/// - `jwt`: Issues a signed JWT and stores it in a cookie.
/// {@endtemplate}
///
/// Options that configure auth providers, storage, and session strategies.
class AuthOptions {
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
    this.sessionAuth,
    this.httpClient,
    this.tokenStore,
    this.enforceCsrf = true,
    this.rbac = const RbacOptions(),
    this.policies = const PolicyOptions(),
    this.callbacks = const AuthCallbacks(),
  });

  /// List of configured auth providers.
  final List<AuthProvider> providers;

  /// Adapter used for persistence (users, accounts, sessions).
  final AuthAdapter adapter;

  /// Session storage strategy.
  final AuthSessionStrategy sessionStrategy;

  /// JWT configuration when using `AuthSessionStrategy.jwt`.
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

  /// Session auth service (defaults to `SessionAuth.instance`).
  final SessionAuthService? sessionAuth;

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
  final AuthCallbacks callbacks;

  AuthOptions copyWith({
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
    SessionAuthService? sessionAuth,
    http.Client? httpClient,
    AuthVerificationTokenStore? tokenStore,
    bool? enforceCsrf,
    RbacOptions? rbac,
    PolicyOptions? policies,
    AuthCallbacks? callbacks,
  }) {
    return AuthOptions(
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
      sessionAuth: sessionAuth ?? this.sessionAuth,
      httpClient: httpClient ?? this.httpClient,
      tokenStore: tokenStore ?? this.tokenStore,
      enforceCsrf: enforceCsrf ?? this.enforceCsrf,
      rbac: rbac ?? this.rbac,
      policies: policies ?? this.policies,
      callbacks: callbacks ?? this.callbacks,
    );
  }
}
