import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'account_policy.dart';
import 'api_key.dart';
import 'auth_config.dart';
import 'authorization.dart';
import 'browser.dart';
import 'browser_validator.dart';
import 'callbacks.dart';
import 'deployment.dart';
import 'framework_session.dart';
import 'jwt.dart';
import 'models.dart';
import 'options.dart';
import 'password_policy.dart';
import 'plugin.dart';
import 'providers.dart';
import 'rate_limit.dart';
import 'runtime_posture.dart';
import 'store.dart';

/// Focused, typed presets for common auth deployment shapes.
///
/// Providers and plugins remain explicit inputs. Presets choose coherent
/// runtime and adapter settings but never register capabilities on behalf of
/// the application.
abstract final class AuthDeploymentPresets {
  /// Ephemeral HTTP-friendly settings for local development and tests.
  ///
  /// Uses an in-memory store, local-development posture, direct proxy policy,
  /// and a development cookie policy with `secure: false`. [trustedOrigins]
  /// accepts HTTP or HTTPS origins, which are lowercased, deduplicated, and
  /// stripped of default ports before storage. Origins with credentials,
  /// paths, queries, or fragments throw an [ArgumentError]. Lifecycle delivery
  /// defaults to disabled, and [providers] and [plugins] remain caller-supplied.
  static AuthDeployment<TContext> localDevelopment<TContext>({
    required Iterable<AuthProvider> providers,
    Iterable<AuthServerPlugin<TContext>> plugins = const [],
    Iterable<Uri> trustedOrigins = const [],
    AuthLifecycleDelivery<TContext>? lifecycleDelivery,
    AuthFrameworkSessionHooks<TContext>? frameworkSessionHooks,
    AuthRateLimiter<TContext>? rateLimiter,
    String basePath = '/auth',
  }) {
    final origins = _normalizeOrigins(trustedOrigins);
    final delivery =
        lifecycleDelivery ?? const AuthLifecycleDelivery.disabled();
    return AuthDeployment<TContext>.custom(
      options: AuthOptions<TContext>(
        providers: providers.toList(growable: false),
        plugins: _plugins(plugins),
        store: InMemoryAuthStore(),
        storeMode: AuthStoreMode.ephemeral,
        runtimeMode: AuthRuntimeMode.localDevelopment,
        rateLimiter: rateLimiter,
        browserProtection: AuthBrowserProtectionOptions(
          trustedOrigins: origins,
        ),
        cookiePolicy: AuthCookiePolicy.development,
        passwordResetSender: delivery.passwordReset,
        emailChangeSender: delivery.emailChange,
        accountDeletionSender: delivery.accountDeletion,
        frameworkSessionHooks:
            frameworkSessionHooks ?? AuthFrameworkSessionHooks<TContext>(),
        basePath: basePath,
      ),
      configuration: _sessionConfiguration(
        strategy: AuthSessionStrategy.session,
      ),
      proxyPolicy: const AuthProxyPolicy.direct(),
    );
  }

  /// HTTPS cookie and durable server-session settings for production apps.
  ///
  /// Requires a durable [store], HTTPS origins in [boundary], a
  /// [lifecycleDelivery], and [rateLimiter]. Both session ages must be
  /// positive, with [sessionUpdateAge] shorter than [sessionMaxAge]. The result
  /// enforces production browser protection, secure cookies, CSRF, and the
  /// supplied account, password, role, policy, and callback settings.
  static AuthDeployment<TContext> secureSessionProduction<TContext>({
    required AuthStore store,
    required Iterable<AuthProvider> providers,
    required AuthProductionBoundary boundary,
    required AuthLifecycleDelivery<TContext> lifecycleDelivery,
    AuthFrameworkSessionHooks<TContext>? frameworkSessionHooks,
    required AuthRateLimiter<TContext> rateLimiter,
    required bool requireVerifiedEmail,
    Iterable<AuthServerPlugin<TContext>> plugins = const [],
    Duration sessionMaxAge = const Duration(days: 30),
    Duration sessionUpdateAge = const Duration(hours: 24),
    SameSite sameSite = SameSite.lax,
    String? cookieDomain,
    String basePath = '/auth',
    AuthAccountPolicy accountPolicy = AuthAccountPolicy.production,
    PasswordPolicy passwordPolicy = const PasswordPolicy(),
    RbacOptions rbac = const RbacOptions(),
    PolicyOptions policies = const PolicyOptions(),
    AuthCallbacks<TContext>? callbacks,
    http.Client? httpClient,
  }) {
    _requireDurableStore(store);
    _validateSessionAges(sessionMaxAge, sessionUpdateAge);
    final options = _productionOptions<TContext>(
      store: store,
      providers: providers,
      plugins: plugins,
      boundary: boundary,
      lifecycleDelivery: lifecycleDelivery,
      rateLimiter: rateLimiter,
      requireVerifiedEmail: requireVerifiedEmail,
      sessionStrategy: AuthSessionStrategy.session,
      sessionMaxAge: sessionMaxAge,
      sessionUpdateAge: sessionUpdateAge,
      cookiePolicy: _productionCookiePolicy(
        sameSite: sameSite,
        domain: cookieDomain,
      ),
      basePath: basePath,
      accountPolicy: accountPolicy,
      passwordPolicy: passwordPolicy,
      rbac: rbac,
      policies: policies,
      callbacks: callbacks,
      httpClient: httpClient,
      frameworkSessionHooks: frameworkSessionHooks,
    );
    return AuthDeployment<TContext>.custom(
      options: options,
      configuration: _sessionConfiguration(
        strategy: AuthSessionStrategy.session,
        maxAge: sessionMaxAge,
        updateAge: sessionUpdateAge,
      ),
      proxyPolicy: boundary.proxyPolicy,
    );
  }

  /// Durable JWT issuance and verification settings for API deployments.
  ///
  /// Requires a durable [store], HTTPS [boundary], non-empty [audience], and
  /// an HTTPS [issuer]. [algorithm] must be HS256, HS384, or HS512, with a
  /// UTF-8 [jwtSecret] of at least 32, 48, or 64 bytes respectively. [tokenMaxAge]
  /// must be positive. JWT cookies are secure; [exposeJwtTokenInSessionResponse]
  /// explicitly opts into including the raw token in session responses.
  static AuthDeployment<TContext> jwtApiProduction<TContext>({
    required AuthStore store,
    required Iterable<AuthProvider> providers,
    required AuthProductionBoundary boundary,
    required AuthLifecycleDelivery<TContext> lifecycleDelivery,
    AuthFrameworkSessionHooks<TContext>? frameworkSessionHooks,
    required AuthRateLimiter<TContext> rateLimiter,
    required bool requireVerifiedEmail,
    required bool exposeJwtTokenInSessionResponse,
    required String jwtSecret,
    required Uri issuer,
    required Iterable<String> audience,
    Iterable<AuthServerPlugin<TContext>> plugins = const [],
    Duration tokenMaxAge = const Duration(hours: 1),
    String algorithm = 'HS256',
    String cookieName = 'auth_token',
    SameSite sameSite = SameSite.lax,
    String? cookieDomain,
    String basePath = '/auth',
    AuthAccountPolicy accountPolicy = AuthAccountPolicy.production,
    PasswordPolicy passwordPolicy = const PasswordPolicy(),
    RbacOptions rbac = const RbacOptions(),
    PolicyOptions policies = const PolicyOptions(),
    AuthCallbacks<TContext>? callbacks,
    http.Client? httpClient,
  }) {
    _requireDurableStore(store);
    final normalizedIssuer = _normalizeIssuer(issuer);
    final normalizedAudience = _nonEmptyValues(audience, 'audience');
    final normalizedAlgorithm = algorithm.trim().toUpperCase();
    if (!const <String>{
      'HS256',
      'HS384',
      'HS512',
    }.contains(normalizedAlgorithm)) {
      throw ArgumentError.value(
        algorithm,
        'algorithm',
        'must be HS256, HS384, or HS512 for a shared-secret preset',
      );
    }
    _requireJwtSecret(jwtSecret, normalizedAlgorithm);
    if (tokenMaxAge <= Duration.zero) {
      throw ArgumentError.value(
        tokenMaxAge,
        'tokenMaxAge',
        'must be greater than zero',
      );
    }
    final jwt = JwtSessionOptions(
      secret: jwtSecret,
      issuer: normalizedIssuer,
      audience: normalizedAudience,
      maxAge: tokenMaxAge,
      algorithm: normalizedAlgorithm,
      cookieName: cookieName,
      secure: true,
      sameSite: sameSite,
    );
    final options = _productionOptions<TContext>(
      store: store,
      providers: providers,
      plugins: plugins,
      boundary: boundary,
      lifecycleDelivery: lifecycleDelivery,
      rateLimiter: rateLimiter,
      requireVerifiedEmail: requireVerifiedEmail,
      sessionStrategy: AuthSessionStrategy.jwt,
      sessionMaxAge: tokenMaxAge,
      sessionUpdateAge: null,
      cookiePolicy: _productionCookiePolicy(
        sameSite: sameSite,
        domain: cookieDomain,
      ),
      jwtOptions: jwt,
      exposeJwtTokenInSessionResponse: exposeJwtTokenInSessionResponse,
      basePath: basePath,
      accountPolicy: accountPolicy,
      passwordPolicy: passwordPolicy,
      rbac: rbac,
      policies: policies,
      callbacks: callbacks,
      httpClient: httpClient,
      frameworkSessionHooks: frameworkSessionHooks,
    );
    return AuthDeployment<TContext>.custom(
      options: options,
      configuration: _sessionConfiguration(
        strategy: AuthSessionStrategy.jwt,
        maxAge: tokenMaxAge,
        jwt: jwt,
      ),
      proxyPolicy: boundary.proxyPolicy,
    );
  }

  /// Durable session management plus API-key authentication for services.
  ///
  /// Requires durable [store] and [apiKeyStore] implementations; an in-memory
  /// API-key store is rejected. The API-key plugin is prepended to [plugins].
  /// [allowSessionExchange] controls whether API-key requests may exchange
  /// into sessions, while key and session lifetimes are validated before
  /// production options are built.
  static AuthApiKeyDeployment<TContext> serviceApiKeyProduction<TContext>({
    required AuthStore store,
    required AuthApiKeyStore apiKeyStore,
    required Iterable<AuthProvider> providers,
    required AuthProductionBoundary boundary,
    required AuthLifecycleDelivery<TContext> lifecycleDelivery,
    AuthFrameworkSessionHooks<TContext>? frameworkSessionHooks,
    required AuthRateLimiter<TContext> rateLimiter,
    required bool requireVerifiedEmail,
    required bool allowSessionExchange,
    Iterable<AuthServerPlugin<TContext>> plugins = const [],
    String keyPrefix = 'rka',
    Duration defaultKeyLifetime = const Duration(days: 90),
    Duration maximumKeyLifetime = const Duration(days: 365),
    Duration sessionMaxAge = const Duration(days: 30),
    Duration sessionUpdateAge = const Duration(hours: 24),
    SameSite sameSite = SameSite.lax,
    String? cookieDomain,
    String basePath = '/auth',
    AuthAccountPolicy accountPolicy = AuthAccountPolicy.production,
    PasswordPolicy passwordPolicy = const PasswordPolicy(),
    RbacOptions rbac = const RbacOptions(),
    PolicyOptions policies = const PolicyOptions(),
    AuthCallbacks<TContext>? callbacks,
    http.Client? httpClient,
  }) {
    _requireDurableStore(store);
    if (apiKeyStore is InMemoryAuthApiKeyStore) {
      throw ArgumentError.value(
        apiKeyStore,
        'apiKeyStore',
        'production API keys require a durable AuthApiKeyStore',
      );
    }
    _validateSessionAges(sessionMaxAge, sessionUpdateAge);
    final apiKeys = AuthApiKeyPlugin<TContext>(
      store: apiKeyStore,
      keyPrefix: keyPrefix,
      defaultLifetime: defaultKeyLifetime,
      maxLifetime: maximumKeyLifetime,
      sessionExchangeEnabled: allowSessionExchange,
    );
    final composedPlugins = <AuthServerPlugin<TContext>>[apiKeys, ...plugins];
    final options = _productionOptions<TContext>(
      store: store,
      providers: providers,
      plugins: composedPlugins,
      boundary: boundary,
      lifecycleDelivery: lifecycleDelivery,
      rateLimiter: rateLimiter,
      requireVerifiedEmail: requireVerifiedEmail,
      sessionStrategy: AuthSessionStrategy.session,
      sessionMaxAge: sessionMaxAge,
      sessionUpdateAge: sessionUpdateAge,
      cookiePolicy: _productionCookiePolicy(
        sameSite: sameSite,
        domain: cookieDomain,
      ),
      basePath: basePath,
      accountPolicy: accountPolicy,
      passwordPolicy: passwordPolicy,
      rbac: rbac,
      policies: policies,
      callbacks: callbacks,
      httpClient: httpClient,
      frameworkSessionHooks: frameworkSessionHooks,
    );
    return AuthApiKeyDeployment<TContext>.custom(
      options: options,
      configuration: _sessionConfiguration(
        strategy: AuthSessionStrategy.session,
        maxAge: sessionMaxAge,
        updateAge: sessionUpdateAge,
      ),
      proxyPolicy: boundary.proxyPolicy,
      apiKeys: apiKeys,
    );
  }
}

AuthOptions<TContext> _productionOptions<TContext>({
  required AuthStore store,
  required Iterable<AuthProvider> providers,
  required Iterable<AuthServerPlugin<TContext>> plugins,
  required AuthProductionBoundary boundary,
  required AuthLifecycleDelivery<TContext> lifecycleDelivery,
  required AuthRateLimiter<TContext> rateLimiter,
  required bool requireVerifiedEmail,
  required AuthSessionStrategy sessionStrategy,
  required Duration sessionMaxAge,
  required Duration? sessionUpdateAge,
  required AuthCookiePolicy cookiePolicy,
  required String basePath,
  required AuthAccountPolicy accountPolicy,
  required PasswordPolicy passwordPolicy,
  required RbacOptions rbac,
  required PolicyOptions policies,
  JwtSessionOptions jwtOptions = const JwtSessionOptions(secret: ''),
  bool exposeJwtTokenInSessionResponse = false,
  AuthCallbacks<TContext>? callbacks,
  http.Client? httpClient,
  AuthFrameworkSessionHooks<TContext>? frameworkSessionHooks,
}) {
  return AuthOptions<TContext>(
    providers: providers.toList(growable: false),
    plugins: _plugins(plugins),
    store: store,
    storeMode: AuthStoreMode.durable,
    runtimeMode: AuthRuntimeMode.production,
    productionBoundary: boundary,
    sessionStrategy: sessionStrategy,
    rateLimiter: rateLimiter,
    browserProtection: AuthBrowserProtectionOptions.production(
      trustedOrigins: boundary.trustedOrigins,
    ),
    cookiePolicy: cookiePolicy,
    accountPolicy: accountPolicy,
    passwordPolicy: passwordPolicy,
    jwtOptions: jwtOptions,
    sessionMaxAge: sessionMaxAge,
    sessionUpdateAge: sessionUpdateAge,
    passwordResetSender: lifecycleDelivery.passwordReset,
    emailChangeSender: lifecycleDelivery.emailChange,
    accountDeletionSender: lifecycleDelivery.accountDeletion,
    basePath: basePath,
    httpClient: httpClient,
    enforceCsrf: true,
    requireVerifiedEmail: requireVerifiedEmail,
    exposeJwtTokenInSessionResponse: exposeJwtTokenInSessionResponse,
    rbac: rbac,
    policies: policies,
    callbacks: callbacks,
    frameworkSessionHooks:
        frameworkSessionHooks ?? AuthFrameworkSessionHooks<TContext>(),
  );
}

AuthConfig _sessionConfiguration({
  required AuthSessionStrategy strategy,
  Duration? maxAge,
  Duration? updateAge,
  JwtSessionOptions? jwt,
}) {
  final defaults = AuthConfig.defaults();
  return defaults.copyWith(
    jwt: jwt == null
        ? defaults.jwt
        : AuthJwtConfig(
            enabled: true,
            issuer: jwt.issuer,
            audience: jwt.audience ?? const <String>[],
            requiredClaims: const <String>['exp'],
            jwksUri: null,
            jwksCacheTtl: const Duration(minutes: 5),
            clockSkew: const Duration(seconds: 60),
            algorithms: <String>[jwt.algorithm],
            inlineKeys: <Map<String, dynamic>>[
              jwtSecretKey(jwt.secret).toJson(),
            ],
            header: jwt.header,
            bearerPrefix: jwt.bearerPrefix,
          ),
    session: AuthSessionConfig(
      strategy: strategy,
      maxAge: maxAge,
      updateAge: updateAge,
      rememberMe: defaults.session.rememberMe,
    ),
  );
}

List<AuthServerPlugin<TContext>> _plugins<TContext>(
  Iterable<AuthServerPlugin<TContext>> plugins,
) {
  final values = plugins.toList(growable: false);
  final ids = <String>{};
  for (final plugin in values) {
    final id = plugin.id.trim();
    if (id.isEmpty || !ids.add(id)) {
      throw ArgumentError.value(
        plugin.id,
        'plugins',
        id.isEmpty
            ? 'plugin IDs must be non-empty'
            : 'plugin IDs must be unique',
      );
    }
  }
  return List<AuthServerPlugin<TContext>>.unmodifiable(values);
}

void _requireDurableStore(AuthStore store) {
  if (store is InMemoryAuthStore || store is CallbackAuthStore) {
    throw ArgumentError.value(
      store,
      'store',
      'production presets require a durable AuthStore',
    );
  }
}

void _requireJwtSecret(String secret, String algorithm) {
  final minimumBytes = switch (algorithm) {
    'HS384' => 48,
    'HS512' => 64,
    _ => 32,
  };
  if (utf8.encode(secret).length < minimumBytes) {
    throw ArgumentError.value(
      '<redacted>',
      'jwtSecret',
      'must contain at least $minimumBytes UTF-8 bytes for $algorithm',
    );
  }
}

void _validateSessionAges(Duration maximumAge, Duration updateAge) {
  if (maximumAge <= Duration.zero) {
    throw ArgumentError.value(
      maximumAge,
      'sessionMaxAge',
      'must be greater than zero',
    );
  }
  if (updateAge <= Duration.zero || updateAge >= maximumAge) {
    throw ArgumentError.value(
      updateAge,
      'sessionUpdateAge',
      'must be greater than zero and less than sessionMaxAge',
    );
  }
}

AuthCookiePolicy _productionCookiePolicy({
  required SameSite sameSite,
  required String? domain,
}) {
  final normalizedDomain = domain?.trim();
  if (domain != null && normalizedDomain!.isEmpty) {
    throw ArgumentError.value(domain, 'cookieDomain', 'must be non-empty');
  }
  return AuthCookiePolicy(
    httpOnly: true,
    secure: true,
    sameSite: sameSite,
    domain: normalizedDomain,
  );
}

List<String> _normalizeOrigins(Iterable<Uri> origins) {
  final normalized = origins
      .map(_normalizeOrigin)
      .toSet()
      .toList(growable: false);
  return List<String>.unmodifiable(normalized);
}

String _normalizeOrigin(Uri origin) {
  final scheme = origin.scheme.toLowerCase();
  if ((scheme != 'http' && scheme != 'https') ||
      origin.host.isEmpty ||
      origin.userInfo.isNotEmpty ||
      origin.query.isNotEmpty ||
      origin.fragment.isNotEmpty ||
      (origin.path.isNotEmpty && origin.path != '/')) {
    throw ArgumentError.value(
      origin,
      'trustedOrigins',
      'must be an HTTP origin without credentials, path, query, or fragment',
    );
  }
  final defaultPort = scheme == 'https' ? 443 : 80;
  final port = origin.hasPort && origin.port != defaultPort
      ? ':${origin.port}'
      : '';
  final normalizedHost = origin.host.contains(':')
      ? '[${origin.host.toLowerCase()}]'
      : origin.host.toLowerCase();
  return '$scheme://$normalizedHost$port';
}

String _normalizeIssuer(Uri issuer) {
  if (issuer.scheme.toLowerCase() != 'https' || issuer.host.isEmpty) {
    throw ArgumentError.value(
      issuer,
      'issuer',
      'must be an absolute HTTPS URI',
    );
  }
  if (issuer.userInfo.isNotEmpty ||
      issuer.query.isNotEmpty ||
      issuer.fragment.isNotEmpty) {
    throw ArgumentError.value(
      issuer,
      'issuer',
      'must not contain credentials, a query, or a fragment',
    );
  }
  return issuer.toString().replaceFirst(RegExp(r'/$'), '');
}

List<String> _nonEmptyValues(Iterable<String> values, String name) {
  final normalized = values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList(growable: false);
  if (normalized.isEmpty) {
    throw ArgumentError.value(normalized, name, 'must not be empty');
  }
  return List<String>.unmodifiable(normalized);
}
