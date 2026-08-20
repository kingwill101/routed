// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:server_auth/server_auth.dart'
    show
        AuthConfig,
        AuthGateRegistry,
        GateDefinition,
        GuardDefinition,
        AuthGuardRegistry,
        HaigateConfig,
        materializeJwtVerifier,
        materializeOAuthIntrospectionOptions,
        RememberTokenStore,
        resolveConfiguredGateCallback,
        resolveConfiguredGuard,
        AuthStore,
        JwtVerifier,
        AuthRuntime,
        resolveAuthOptions,
        SessionRememberMeConfig,
        syncManagedGateDefinitions,
        syncManagedGuardDefinitions,
        syncManagedPolicyBindings,
        syncManagedRbacAbilities,
        AuthOptions;
import 'package:routed_auth/src/auth/manager/auth_manager.dart';
import 'package:routed_auth/src/auth/routes.dart';
import 'package:routed_auth/src/auth/haigate.dart';
import 'package:routed_auth/src/auth/jwt.dart'
    show jwtAuthenticationWithVerifier;
import 'package:routed_auth/src/auth/oauth.dart';
import 'package:routed_auth/src/auth/session_auth.dart';
import 'package:routed_core/src/container/container.dart';
import 'package:routed_core/src/context/context.dart';
import 'package:routed_core/src/engine/engine.dart';
import 'package:routed_core/src/engine/middleware_registry.dart';
import 'package:routed_core/src/provider/provider.dart';
import 'package:routed_core/src/provider/typed_provider.dart';
import 'package:routed_core/src/response.dart';
import 'package:routed_core/src/router/types.dart';

/// Creates a provider coupled to one Routed deployment binding.
///
/// This helper remains internal to Routed's `src` libraries; the public
/// deployment extension is the user-facing entry point.
AuthServiceProvider createDeploymentAuthServiceProvider({
  required AuthConfig configuration,
  required bool requireDurableStore,
  required AuthOptions<EngineContext> options,
}) => AuthServiceProvider._deployment(
  configuration: configuration,
  requireDurableStore: requireDurableStore,
  expectedOptions: options,
);

/// Service provider that boots routed auth infrastructure.
///
/// Registers JWT and OAuth middleware, session auth defaults, and binds an
/// `AuthManager` when `AuthOptions` is available in the container.
class AuthServiceProvider extends ServiceProvider
    with ProvidesTypedConfiguration<AuthConfig> {
  AuthServiceProvider({
    http.Client? httpClient,
    AuthConfig? configuration,
    this.requireDurableStore = false,
  }) : _httpClient = httpClient ?? http.Client(),
       configuration = configuration ?? AuthConfig.defaults(),
       _expectedDeploymentOptions = null;

  AuthServiceProvider._deployment({
    required this.configuration,
    required this.requireDurableStore,
    required AuthOptions<EngineContext> expectedOptions,
  }) : _httpClient = http.Client(),
       _expectedDeploymentOptions = expectedOptions;

  @override
  final AuthConfig configuration;

  final http.Client _httpClient;

  /// Rejects intentionally ephemeral auth storage during provider boot.
  /// Enable this for production deployments.
  final bool requireDurableStore;

  /// Options that a Routed deployment expects [Container] to contain.
  ///
  /// Deployment-created providers use this identity check to fail startup
  /// when `deployment.bindTo` was omitted or an unrelated auth context was
  /// bound instead. Direct providers leave this unset so they can continue to
  /// provide config-only JWT and gate middleware without an [AuthManager].
  final AuthOptions<EngineContext>? _expectedDeploymentOptions;
  JwtVerifier? _jwtVerifier;
  Middleware? _oauthMiddleware;
  SessionAuthService? _sessionAuth;
  AuthConfig? _resolvedConfig;
  bool _ownsAuthManager = false;
  final Set<String> _managedConfigGuards = <String>{};
  final Set<String> _managedConfigGates = <String>{};
  final Set<String> _managedGateMiddleware = <String>{};
  final Set<String> _managedRbacAbilities = <String>{};
  final Set<String> _managedPolicyAbilities = <String>{};
  @override
  void register(Container container) {
    final registry = container.get<MiddlewareRegistry>();
    registry.register(
      'routed.auth.jwt',
      (_) => _jwtVerifier == null
          ? _passthrough
          : jwtAuthenticationWithVerifier(_jwtVerifier!),
    );
    registry.register(
      'routed.auth.oauth2',
      (_) => _oauthMiddleware ?? _passthrough,
    );
  }

  @override
  Future<void> boot(Container container) async {
    _applyConfig(container, configuration);

    final engine = container.has<Engine>() ? container.get<Engine>() : null;
    final manager = container.has<AuthManager>()
        ? container.get<AuthManager>()
        : null;
    if (engine == null || manager == null) {
      return;
    }

    // Bind routes to the live container instance so handlers keep using the
    // current manager after config reloads replace the previously bound one.
    AuthRoutes(
      manager,
      managerOf: () =>
          container.has<AuthManager>() ? container.get<AuthManager>() : manager,
    ).register(engine.defaultRouter);
  }

  void _applyConfig(Container container, AuthConfig config) {
    final resolved = config;
    _resolvedConfig = resolved;

    final jwt = resolved.jwt;
    _jwtVerifier = materializeJwtVerifier(
      enabled: jwt.enabled,
      issuer: jwt.issuer,
      audience: jwt.audience,
      requiredClaims: jwt.requiredClaims,
      jwksUri: jwt.jwksUri,
      inlineKeys: jwt.inlineKeys,
      algorithms: jwt.algorithms,
      clockSkew: jwt.clockSkew,
      jwksCacheTtl: jwt.jwksCacheTtl,
      header: jwt.header,
      bearerPrefix: jwt.bearerPrefix,
      httpClient: _httpClient,
    );

    final oauth = resolved.oauth2Introspection;
    final oauthOptions = materializeOAuthIntrospectionOptions(
      enabled: oauth.enabled,
      endpoint: oauth.endpoint,
      clientId: oauth.clientId,
      clientSecret: oauth.clientSecret,
      tokenTypeHint: oauth.tokenTypeHint,
      cacheTtl: oauth.cacheTtl,
      clockSkew: oauth.clockSkew,
      additionalParameters: oauth.additionalParameters,
    );
    if (oauth.enabled && oauthOptions == null) {
      throw ProviderConfigException(
        'auth.oauth2.introspection.endpoint is required when enabled',
      );
    }
    _oauthMiddleware = oauthOptions == null
        ? null
        : oauth2Introspection(oauthOptions, httpClient: _httpClient);

    if (_jwtVerifier != null) {
      container.instance<JwtVerifier>(_jwtVerifier!);
    }

    _sessionAuth = _configureSessionAuth(
      container,
      resolved.session.rememberMe,
    );
    container.instance<SessionAuthService>(_sessionAuth!);

    final guardRegistry = _resolveGuardRegistry(container);
    guardRegistry.register(
      'authenticated',
      requireAuthenticated(sessionAuth: _sessionAuth!),
    );
    syncManagedGuardDefinitions<EngineContext, Response, GuardDefinition>(
      guardRegistry,
      resolved.guards,
      buildGuard: (_, definition) =>
          resolveConfiguredGuard<EngineContext, Response>(
            definition: definition,
            authenticatedGuard: (realm) =>
                requireAuthenticated(realm: realm, sessionAuth: _sessionAuth!),
            rolesGuard: (roles, any) =>
                requireRoles(roles, sessionAuth: _sessionAuth!, any: any),
          ),
      managed: _managedConfigGuards,
      preserve: const <String>{'authenticated'},
    );

    final gateRegistry = _resolveGateRegistry(container);
    final middlewareRegistry = container.get<MiddlewareRegistry>();
    _configureHaigate(resolved.haigate, gateRegistry, middlewareRegistry);

    _applyAuthManager(container);
  }

  void _applyAuthManager(Container container) {
    final expectedOptions = _expectedDeploymentOptions;
    if (expectedOptions != null) {
      if (!container.has<AuthOptions<EngineContext>>()) {
        throw StateError(
          'The Routed auth deployment was not bound to this engine. '
          'Call deployment.bindTo(engine) before Engine.initialize().',
        );
      }
      final boundOptions = container.get<AuthOptions<EngineContext>>();
      if (!identical(boundOptions, expectedOptions)) {
        throw StateError(
          'The Routed auth deployment options do not match the options bound '
          'to this engine. Bind the same deployment used to create the auth '
          'service provider.',
        );
      }
    }

    if (!container.has<AuthOptions<EngineContext>>()) {
      if (_ownsAuthManager) {
        container.remove<AuthManager>();
        SessionAuth.setSessionUpdater(null);
        _ownsAuthManager = false;
      }
      return;
    }

    if (container.has<AuthManager>() && !_ownsAuthManager) {
      return;
    }

    final options = container.get<AuthOptions<EngineContext>>();
    final store = container.has<AuthStore>()
        ? container.get<AuthStore>()
        : options.store;
    final configSession = _resolvedConfig?.session;
    final resolvedOptions = resolveAuthOptions<EngineContext>(
      options: options,
      store: store,
      httpClient: _httpClient,
      sessionStrategy: configSession?.strategy,
      sessionMaxAge: configSession?.maxAge,
      sessionUpdateAge: configSession?.updateAge,
    );

    final runtime = _resolveAuthRuntime(container, resolvedOptions);
    final manager = AuthManager(
      resolvedOptions,
      sessionAuth: _sessionAuth,
      runtime: runtime,
    );
    container.instance<AuthManager>(manager);
    _ownsAuthManager = true;

    SessionAuth.setSessionUpdater(manager.updateSession);

    final registry = _resolveGateRegistry(container);
    syncManagedRbacAbilities<EngineContext>(
      registry,
      resolvedOptions.rbac.abilities,
      managed: _managedRbacAbilities,
    );
    syncManagedPolicyBindings<EngineContext>(
      registry,
      resolvedOptions.policies.bindings,
      managed: _managedPolicyAbilities,
    );
  }

  AuthRuntime<EngineContext> _resolveAuthRuntime(
    Container container,
    AuthOptions<EngineContext> options,
  ) {
    if (container.has<AuthRuntime<EngineContext>>()) {
      final runtime = container.get<AuthRuntime<EngineContext>>();
      if (requireDurableStore) runtime.requireDurableStoreOrThrow();
      return runtime;
    }
    final runtime = AuthRuntime<EngineContext>(
      options: options,
      requireDurableStore: requireDurableStore,
    );
    container.instance<AuthRuntime<EngineContext>>(runtime);
    return runtime;
  }

  AuthGuardRegistry<EngineContext, Response> _resolveGuardRegistry(
    Container container,
  ) {
    if (container.has<AuthGuardRegistry<EngineContext, Response>>()) {
      try {
        return container.get<AuthGuardRegistry<EngineContext, Response>>();
      } catch (_) {
        // Fall through to create a new registry instance.
      }
    }
    container.instance<AuthGuardRegistry<EngineContext, Response>>(
      guardRegistry,
    );
    return guardRegistry;
  }

  AuthGateRegistry<EngineContext> _resolveGateRegistry(Container container) {
    if (container.has<AuthGateRegistry<EngineContext>>()) {
      try {
        return container.get<AuthGateRegistry<EngineContext>>();
      } catch (_) {
        // Fall through to create a new registry instance.
      }
    }
    container.instance<AuthGateRegistry<EngineContext>>(gateRegistry);
    return gateRegistry;
  }

  SessionAuthService _configureSessionAuth(
    Container container,
    SessionRememberMeConfig rememberMe,
  ) {
    RememberTokenStore? rememberStore;
    if (container.has<RememberTokenStore>()) {
      try {
        rememberStore = container.get<RememberTokenStore>();
      } catch (_) {
        rememberStore = null;
      }
    }

    return SessionAuth.configure(
      rememberStore: rememberStore,
      rememberCookieName: rememberMe.cookieName,
      defaultRememberDuration: rememberMe.duration,
    );
  }

  void _configureHaigate(
    HaigateConfig config,
    AuthGateRegistry<EngineContext> registry,
    MiddlewareRegistry middlewareRegistry,
  ) {
    final defaults = config.defaults;
    final middlewareIdsByAbility = <String, String>{};
    final newMiddlewareIds = <String>{};

    final definitions = config.enabled
        ? config.abilities
        : const <String, GateDefinition>{};
    final newAbilities =
        syncManagedGateDefinitions<EngineContext, GateDefinition>(
          registry,
          definitions,
          buildGate: (ability, definition) {
            final callback = resolveConfiguredGateCallback<EngineContext>(
              definition,
            );
            if (callback == null) {
              return null;
            }
            middlewareIdsByAbility[ability] = 'routed.auth.gate.$ability';
            return callback;
          },
          managed: _managedConfigGates,
        );

    for (final ability in newAbilities) {
      final middlewareId = middlewareIdsByAbility[ability];
      if (middlewareId == null) {
        continue;
      }
      middlewareRegistry.register(
        middlewareId,
        (_) => Haigate.middleware(
          [ability],
          deniedStatusCode: defaults.statusCode,
          deniedMessage: defaults.message,
        ),
      );
      newMiddlewareIds.add(middlewareId);
    }

    final toReset = _managedGateMiddleware.difference(newMiddlewareIds);
    for (final id in toReset) {
      middlewareRegistry.register(id, (_) => _passthrough);
    }
    _managedGateMiddleware
      ..clear()
      ..addAll(newMiddlewareIds);
  }

  FutureOr<Response> _passthrough(EngineContext ctx, Next next) => next();
}
