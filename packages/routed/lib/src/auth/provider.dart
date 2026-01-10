import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:routed/src/auth/auth_adapter.dart';
import 'package:routed/src/auth/auth_manager.dart';
import 'package:routed/src/auth/auth_routes.dart';
import 'package:routed/src/auth/haigate.dart';
import 'package:routed/src/auth/jwt.dart';
import 'package:routed/src/auth/oauth.dart';
import 'package:routed/src/auth/session_auth.dart';
import 'package:routed/src/config/specs/auth.dart';
import 'package:routed/src/container/container.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/engine.dart';
import 'package:routed/src/engine/middleware_registry.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/response.dart';
import 'package:routed/src/router/types.dart';

/// Service provider that boots routed auth infrastructure.
///
/// Registers JWT and OAuth middleware, session auth defaults, and binds an
/// `AuthManager` when `AuthOptions` is available in the container.
class AuthServiceProvider extends ServiceProvider with ProvidesDefaultConfig {
  AuthServiceProvider({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  JwtVerifier? _jwtVerifier;
  Middleware? _oauthMiddleware;
  SessionAuthService? _sessionAuth;
  // ignore: unused_field
  AuthManager? _managedAuthManager;
  bool _ownsAuthManager = false;
  final Set<String> _managedConfigGuards = <String>{};
  final Set<String> _managedConfigGates = <String>{};
  final Set<String> _managedGateMiddleware = <String>{};
  static const AuthConfigSpec spec = AuthConfigSpec();

  @override
  ConfigDefaults get defaultConfig {
    final values = spec.defaultsWithRoot();
    values['http'] = {
      'middleware_sources': {
        'routed.auth': {
          'global': ['routed.auth.jwt', 'routed.auth.oauth2'],
        },
      },
    };
    return ConfigDefaults(
      docs: [
        const ConfigDocEntry(
          path: 'http.middleware_sources',
          type: 'map',
          description:
              'Authentication middleware references registered globally.',
          defaultValue: <String, Object?>{
            'routed.auth': <String, Object?>{
              'global': <String>['routed.auth.jwt', 'routed.auth.oauth2'],
            },
          },
        ),
        ...spec.docs(),
      ],
      values: values,
      schemas: spec.schemaWithRoot(),
    );
  }

  @override
  void register(Container container) {
    final registry = container.get<MiddlewareRegistry>();
    registry.register(
      'routed.auth.jwt',
      (_) => _jwtVerifier?.middleware() ?? _passthrough,
    );
    registry.register(
      'routed.auth.oauth2',
      (_) => _oauthMiddleware ?? _passthrough,
    );

    if (container.has<Config>()) {
      _applyConfig(container, container.get<Config>());
    } else {
      _applyAuthManager(container);
    }
  }

  @override
  Future<void> boot(Container container) async {
    final engine = container.has<Engine>() ? container.get<Engine>() : null;
    final manager = container.has<AuthManager>()
        ? container.get<AuthManager>()
        : null;
    if (engine == null || manager == null) {
      return;
    }

    AuthRoutes(manager).register(engine.defaultRouter);
  }

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    _applyConfig(container, config);
  }

  void _applyConfig(Container container, Config config) {
    final resolved = spec.resolve(config);

    _jwtVerifier = _buildJwtVerifier(resolved);
    _oauthMiddleware = _buildOAuthMiddleware(resolved);

    if (_jwtVerifier != null) {
      container.instance<JwtVerifier>(_jwtVerifier!);
    }

    _sessionAuth = _configureSessionAuth(container, resolved.sessionRememberMe);
    container.instance<SessionAuthService>(_sessionAuth!);

    final guardRegistry = _resolveGuardRegistry(container);
    for (final name in _managedConfigGuards) {
      guardRegistry.unregister(name);
    }
    guardRegistry.register(
      'authenticated',
      requireAuthenticated(sessionAuth: _sessionAuth!),
    );
    _managedConfigGuards
      ..clear()
      ..addAll(_configureGuards(resolved.guards, guardRegistry, _sessionAuth!));

    final gateRegistry = _resolveGateRegistry(container);
    final middlewareRegistry = container.get<MiddlewareRegistry>();
    _configureHaigate(resolved.haigate, gateRegistry, middlewareRegistry);

    _applyAuthManager(container);
  }

  void _applyAuthManager(Container container) {
    if (!container.has<AuthOptions>()) {
      if (_ownsAuthManager) {
        container.remove<AuthManager>();
        _managedAuthManager = null;
        _ownsAuthManager = false;
      }
      return;
    }

    if (container.has<AuthManager>() && !_ownsAuthManager) {
      return;
    }

    final options = container.get<AuthOptions>();
    final adapter = _resolveAuthAdapter(container, options);
    final tokenStore = _resolveTokenStore(container, options);
    final resolvedOptions = options.copyWith(
      adapter: adapter,
      sessionAuth: options.sessionAuth ?? _sessionAuth,
      httpClient: options.httpClient ?? _httpClient,
      tokenStore: tokenStore,
    );

    final manager = AuthManager(resolvedOptions);
    _managedAuthManager = manager;
    container.instance<AuthManager>(manager);
    _ownsAuthManager = true;
  }

  AuthAdapter _resolveAuthAdapter(Container container, AuthOptions options) {
    if (!container.has<AuthAdapter>()) {
      return options.adapter;
    }
    if (options.adapter.runtimeType != AuthAdapter) {
      return options.adapter;
    }
    return container.get<AuthAdapter>();
  }

  AuthVerificationTokenStore? _resolveTokenStore(
    Container container,
    AuthOptions options,
  ) {
    if (options.tokenStore != null) {
      return options.tokenStore;
    }
    if (container.has<AuthVerificationTokenStore>()) {
      return container.get<AuthVerificationTokenStore>();
    }
    return null;
  }

  GuardRegistry _resolveGuardRegistry(Container container) {
    if (container.has<GuardRegistry>()) {
      try {
        return container.get<GuardRegistry>();
      } catch (_) {
        // Fall through to create a new registry instance.
      }
    }
    final guardRegistry = GuardRegistry.instance;
    container.instance<GuardRegistry>(guardRegistry);
    return guardRegistry;
  }

  GateRegistry _resolveGateRegistry(Container container) {
    if (container.has<GateRegistry>()) {
      try {
        return container.get<GateRegistry>();
      } catch (_) {
        // Fall through to create a new registry instance.
      }
    }
    final gateRegistry = GateRegistry.instance;
    container.instance<GateRegistry>(gateRegistry);
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

  Set<String> _configureGuards(
    Map<String, GuardDefinition> guards,
    GuardRegistry registry,
    SessionAuthService sessionAuth,
  ) {
    final managed = <String>{};
    guards.forEach((name, definition) {
      final guard = _buildGuardFromDefinition(definition, sessionAuth);
      if (guard != null) {
        registry.register(name, guard);
        managed.add(name);
      }
    });
    return managed;
  }

  void _configureHaigate(
    HaigateConfig config,
    GateRegistry registry,
    MiddlewareRegistry middlewareRegistry,
  ) {
    final enabled = config.enabled;

    final defaults = config.defaults;

    final newAbilities = <String>{};
    final newMiddlewareIds = <String>{};

    if (enabled) {
      config.abilities.forEach((ability, definition) {
        final trimmed = ability.trim();
        if (trimmed.isEmpty) {
          return;
        }
        final callback = _buildGateFromDefinition(definition);
        if (callback == null) {
          return;
        }

        final managedBefore = _managedConfigGates.contains(trimmed);
        if (managedBefore) {
          registry.unregister(trimmed);
        }

        try {
          registry.register(trimmed, callback);
        } on GateRegistrationException {
          if (!managedBefore) {
            // Preserve user-defined gate registrations when names collide.
            return;
          }
          rethrow;
        }

        newAbilities.add(trimmed);
        final middlewareId = 'routed.auth.gate.$trimmed';
        middlewareRegistry.register(
          middlewareId,
          (_) => Haigate.middleware(
            [trimmed],
            deniedStatusCode: defaults.statusCode,
            deniedMessage: defaults.message,
          ),
        );
        newMiddlewareIds.add(middlewareId);
      });
    }

    for (final ability in _managedConfigGates.difference(newAbilities)) {
      registry.unregister(ability);
    }
    _managedConfigGates
      ..clear()
      ..addAll(newAbilities);

    final toReset = _managedGateMiddleware.difference(newMiddlewareIds);
    for (final id in toReset) {
      middlewareRegistry.register(id, (_) => _passthrough);
    }
    _managedGateMiddleware
      ..clear()
      ..addAll(newMiddlewareIds);
  }

  GateCallback? _buildGateFromDefinition(GateDefinition definition) {
    switch (definition.type) {
      case GateType.guest:
        return (GateEvaluationContext context) => context.principal == null;
      case GateType.authenticated:
        return (GateEvaluationContext context) => context.principal != null;
      case GateType.roles:
        final requiredRoles = definition.roles;
        final any = definition.any;
        final allowGuest = definition.allowGuest;
        if (requiredRoles.isEmpty) {
          return (GateEvaluationContext context) {
            final principal = context.principal;
            if (principal == null) {
              return allowGuest;
            }
            return true;
          };
        }
        return (GateEvaluationContext context) {
          final principal = context.principal;
          if (principal == null) {
            return allowGuest;
          }
          return any
              ? requiredRoles.any(principal.hasRole)
              : requiredRoles.every(principal.hasRole);
        };
    }
  }

  AuthGuard? _buildGuardFromDefinition(
    GuardDefinition definition,
    SessionAuthService sessionAuth,
  ) {
    switch (definition.type) {
      case GuardType.authenticated:
        final realm =
            definition.realm == null || definition.realm!.trim().isEmpty
            ? 'Restricted'
            : definition.realm!;
        return requireAuthenticated(realm: realm, sessionAuth: sessionAuth);
      case GuardType.roles:
        if (definition.roles.isEmpty) {
          return null;
        }
        return requireRoles(
          definition.roles,
          sessionAuth: sessionAuth,
          any: definition.any,
        );
    }
  }

  FutureOr<Response> _passthrough(EngineContext ctx, Next next) => next();

  JwtVerifier? _buildJwtVerifier(AuthConfig config) {
    final settings = config.jwt;
    if (!settings.enabled) {
      return null;
    }

    final options = JwtOptions(
      enabled: true,
      issuer: settings.issuer?.isEmpty ?? true ? null : settings.issuer,
      audience: settings.audience,
      requiredClaims: settings.requiredClaims,
      jwksUri: settings.jwksUri,
      inlineKeys: settings.inlineKeys,
      algorithms: settings.algorithms.isEmpty
          ? const <String>['RS256']
          : settings.algorithms,
      clockSkew: settings.clockSkew,
      jwksCacheTtl: settings.jwksCacheTtl,
      header: settings.header,
      bearerPrefix: settings.bearerPrefix,
    );

    return JwtVerifier(options: options, httpClient: _httpClient);
  }

  Middleware? _buildOAuthMiddleware(AuthConfig config) {
    final settings = config.oauth2Introspection;
    if (!settings.enabled) {
      return null;
    }
    final endpoint = settings.endpoint;
    if (endpoint == null) {
      throw ProviderConfigException(
        'auth.oauth2.introspection.endpoint is required when enabled',
      );
    }

    final options = OAuthIntrospectionOptions(
      endpoint: endpoint,
      clientId: _nullIfEmpty(settings.clientId),
      clientSecret: _nullIfEmpty(settings.clientSecret),
      tokenTypeHint: _nullIfEmpty(settings.tokenTypeHint),
      cacheTtl: settings.cacheTtl,
      clockSkew: settings.clockSkew,
      additionalParameters: settings.additionalParameters,
    );

    return oauth2Introspection(options, httpClient: _httpClient);
  }
}

String? _nullIfEmpty(String? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
