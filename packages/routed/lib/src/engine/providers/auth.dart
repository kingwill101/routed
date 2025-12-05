import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:routed/src/auth/haigate.dart';
import 'package:routed/src/auth/jwt.dart';
import 'package:routed/src/auth/oauth.dart';
import 'package:routed/src/auth/session_auth.dart';
import 'package:routed/src/container/container.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/middleware_registry.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/response.dart';
import 'package:routed/src/router/types.dart';

class AuthServiceProvider extends ServiceProvider with ProvidesDefaultConfig {
  AuthServiceProvider({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  JwtVerifier? _jwtVerifier;
  Middleware? _oauthMiddleware;
  SessionAuthService? _sessionAuth;
  final Set<String> _managedConfigGuards = <String>{};
  final Set<String> _managedConfigGates = <String>{};
  final Set<String> _managedGateMiddleware = <String>{};

  @override
  ConfigDefaults get defaultConfig => const ConfigDefaults(
    docs: <ConfigDocEntry>[
      ConfigDocEntry(
        path: 'auth.jwt.enabled',
        type: 'bool',
        description: 'Enable JWT Bearer authentication middleware.',
        defaultValue: false,
      ),
      ConfigDocEntry(
        path: 'auth.jwt.issuer',
        type: 'string',
        description: 'Required issuer claim value.',
        defaultValue: null,
      ),
      ConfigDocEntry(
        path: 'auth.jwt.audience',
        type: 'list<string>',
        description: 'Allowed audience values (any match passes).',
        defaultValue: <String>[],
      ),
      ConfigDocEntry(
        path: 'auth.jwt.required_claims',
        type: 'list<string>',
        description: 'Claims that must be present in every token.',
        defaultValue: <String>[],
      ),
      ConfigDocEntry(
        path: 'auth.jwt.jwks_url',
        type: 'string',
        description: 'JWKS endpoint used to resolve signing keys.',
        defaultValue: null,
      ),
      ConfigDocEntry(
        path: 'auth.jwt.jwks_cache_ttl',
        type: 'duration',
        description: 'How long JWKS responses are cached.',
        defaultValue: '5m',
      ),
      ConfigDocEntry(
        path: 'auth.jwt.algorithms',
        type: 'list<string>',
        description: 'Allowed signing algorithms (e.g. RS256).',
        defaultValue: ['RS256'],
      ),
      ConfigDocEntry(
        path: 'auth.jwt.clock_skew',
        type: 'duration',
        description: 'Clock skew allowance for exp/nbf validation.',
        defaultValue: '60s',
      ),
      ConfigDocEntry(
        path: 'auth.jwt.keys',
        type: 'list<map>',
        description: 'Inline JWK set used in addition to remote JWKS.',
        defaultValue: <Map<String, Object?>>[],
      ),
      ConfigDocEntry(
        path: 'auth.jwt.header',
        type: 'string',
        description: 'Header name inspected for bearer tokens.',
        defaultValue: 'Authorization',
      ),
      ConfigDocEntry(
        path: 'auth.jwt.bearer_prefix',
        type: 'string',
        description: 'Expected prefix for bearer tokens (default "Bearer ").',
        defaultValue: 'Bearer ',
      ),
      ConfigDocEntry(
        path: 'auth.oauth2.introspection.enabled',
        type: 'bool',
        description: 'Enable RFC 7662 token introspection middleware.',
        defaultValue: false,
      ),
      ConfigDocEntry(
        path: 'auth.oauth2.introspection.endpoint',
        type: 'string',
        description: 'OAuth2 introspection endpoint URL.',
        defaultValue: null,
      ),
      ConfigDocEntry(
        path: 'auth.oauth2.introspection.client_id',
        type: 'string',
        description:
            'Client identifier used when calling the introspection endpoint.',
        defaultValue: null,
      ),
      ConfigDocEntry(
        path: 'auth.oauth2.introspection.client_secret',
        type: 'string',
        description: 'Client secret used for introspection requests.',
        defaultValue: null,
      ),
      ConfigDocEntry(
        path: 'auth.oauth2.introspection.token_type_hint',
        type: 'string',
        description:
            'Optional token type hint passed to the introspection endpoint.',
        defaultValue: null,
      ),
      ConfigDocEntry(
        path: 'auth.oauth2.introspection.cache_ttl',
        type: 'duration',
        description: 'How long introspection results are cached.',
        defaultValue: '30s',
      ),
      ConfigDocEntry(
        path: 'auth.oauth2.introspection.clock_skew',
        type: 'duration',
        description: 'Clock skew allowance for introspection timestamps.',
        defaultValue: '60s',
      ),
      ConfigDocEntry(
        path: 'auth.oauth2.introspection.additional',
        type: 'map<string,string>',
        description:
            'Additional form parameters appended to introspection requests.',
        defaultValue: <String, String>{},
      ),
      ConfigDocEntry(
        path: 'auth.session.remember_me.cookie',
        type: 'string',
        description: 'Cookie name used for remember-me tokens.',
        defaultValue: 'remember_token',
      ),
      ConfigDocEntry(
        path: 'auth.session.remember_me.duration',
        type: 'duration',
        description:
            'Default lifetime applied to remember-me tokens when issued.',
        defaultValue: '30d',
      ),
      ConfigDocEntry(
        path: 'auth.features.haigate.enabled',
        type: 'bool',
        description: 'Enable Haigate authorization registry and middleware.',
        defaultValue: false,
      ),
      ConfigDocEntry(
        path: 'auth.gates.defaults.denied_status',
        type: 'int',
        description:
            'HTTP status returned when a gate denies access (used by default middleware).',
        defaultValue: HttpStatus.forbidden,
      ),
      ConfigDocEntry(
        path: 'auth.gates.defaults.denied_message',
        type: 'string',
        description:
            'Optional body message returned when a gate denies access (used by default middleware).',
        defaultValue: null,
      ),
      ConfigDocEntry(
        path: 'auth.gates.abilities',
        type: 'map',
        description:
            'Declarative Haigate abilities. Entries map ability names to role or authentication checks.',
        defaultValue: <String, Object?>{},
      ),
      ConfigDocEntry(
        path: 'auth.gates.abilities[].type',
        type: 'string',
        description:
            'Ability type. Supported values: authenticated, guest, roles, roles_any.',
        options: ['authenticated', 'guest', 'roles', 'roles_any'],
      ),
      ConfigDocEntry(
        path: 'auth.gates.abilities[].roles',
        type: 'list<string>',
        description:
            'Roles required for the ability (used when type is roles or roles_any).',
        defaultValue: <String>[],
      ),
      ConfigDocEntry(
        path: 'auth.gates.abilities[].any',
        type: 'bool',
        description:
            'If true, any listed role passes (defaults to requiring all roles).',
        defaultValue: false,
      ),
      ConfigDocEntry(
        path: 'auth.gates.abilities[].allow_guest',
        type: 'bool',
        description:
            'Allow guests (no principal) to pass the gate (defaults to false).',
        defaultValue: false,
      ),
      ConfigDocEntry(
        path: 'auth.guards',
        type: 'map',
        description:
            'Named guard definitions consumed by guard middleware (e.g. authenticated, roles).',
        defaultValue: {
          'authenticated': {'type': 'authenticated', 'realm': 'Restricted'},
        },
      ),
      ConfigDocEntry(
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
    ],
  );

  @override
  void register(Container container) {
    final config = container.get<Config>();
    _jwtVerifier = _buildJwtVerifier(config);
    _oauthMiddleware = _buildOAuthMiddleware(config);

    if (_jwtVerifier != null) {
      container.instance<JwtVerifier>(_jwtVerifier!);
    }

    _sessionAuth = _configureSessionAuth(container, config);
    container.instance<SessionAuthService>(_sessionAuth!);

    final guardRegistry = GuardRegistry.instance;
    container.instance<GuardRegistry>(guardRegistry);
    guardRegistry.register(
      'authenticated',
      requireAuthenticated(sessionAuth: _sessionAuth!),
    );
    _managedConfigGuards
      ..clear()
      ..addAll(_configureGuards(config, guardRegistry, _sessionAuth!));

    final gateRegistry = GateRegistry.instance;
    container.instance<GateRegistry>(gateRegistry);

    final registry = container.get<MiddlewareRegistry>();
    _configureHaigate(config, gateRegistry, registry);
    registry.register(
      'routed.auth.jwt',
      (_) => _jwtVerifier?.middleware() ?? _passthrough,
    );
    registry.register(
      'routed.auth.oauth2',
      (_) => _oauthMiddleware ?? _passthrough,
    );
  }

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    _jwtVerifier = _buildJwtVerifier(config);
    _oauthMiddleware = _buildOAuthMiddleware(config);
    if (_jwtVerifier != null) {
      container.instance<JwtVerifier>(_jwtVerifier!);
    }

    _sessionAuth = _configureSessionAuth(container, config);
    container.instance<SessionAuthService>(_sessionAuth!);

    GuardRegistry guardRegistry;
    if (container.has<GuardRegistry>()) {
      try {
        guardRegistry = container.get<GuardRegistry>();
      } catch (_) {
        guardRegistry = GuardRegistry.instance;
      }
    } else {
      guardRegistry = GuardRegistry.instance;
      container.instance<GuardRegistry>(guardRegistry);
    }

    for (final name in _managedConfigGuards) {
      guardRegistry.unregister(name);
    }
    guardRegistry.register(
      'authenticated',
      requireAuthenticated(sessionAuth: _sessionAuth!),
    );
    _managedConfigGuards
      ..clear()
      ..addAll(_configureGuards(config, guardRegistry, _sessionAuth!));

    GateRegistry gateRegistry;
    if (container.has<GateRegistry>()) {
      try {
        gateRegistry = container.get<GateRegistry>();
      } catch (_) {
        gateRegistry = GateRegistry.instance;
        container.instance<GateRegistry>(gateRegistry);
      }
    } else {
      gateRegistry = GateRegistry.instance;
      container.instance<GateRegistry>(gateRegistry);
    }

    final middlewareRegistry = container.get<MiddlewareRegistry>();
    _configureHaigate(config, gateRegistry, middlewareRegistry);
  }

  SessionAuthService _configureSessionAuth(Container container, Config config) {
    final cookieName = config.getString('auth.session.remember_me.cookie', defaultValue: '', allowEmpty: true);

    final rememberDuration = config.getDurationOrNull('auth.session.remember_me.duration');

    RememberTokenStore? rememberStore;
    if (container.has<RememberTokenStore>()) {
      try {
        rememberStore = container.get<RememberTokenStore>();
      } catch (_) {
        rememberStore = null;
      }
    }

    final resolvedCookie = cookieName.isEmpty ? null : cookieName;

    return SessionAuth.configure(
      rememberStore: rememberStore,
      rememberCookieName: resolvedCookie,
      defaultRememberDuration: rememberDuration,
    );
  }

  Set<String> _configureGuards(
    Config config,
    GuardRegistry registry,
    SessionAuthService sessionAuth,
  ) {
    final managed = <String>{};
    final node = config.get<Map<dynamic, dynamic>>('auth.guards');
    if (node is Map) {
      node.forEach((key, value) {
        final guardName = key.toString();
        final guard = _buildGuardFromSpec(value, sessionAuth);
        if (guard != null) {
          registry.register(guardName, guard);
          managed.add(guardName);
        }
      });
    }
    return managed;
  }

  void _configureHaigate(
    Config config,
    GateRegistry registry,
    MiddlewareRegistry middlewareRegistry,
  ) {
    final enabled = config.getBool('auth.features.haigate.enabled');

    final defaults = _resolveGateDefaults(config);

    final newAbilities = <String>{};
    final newMiddlewareIds = <String>{};

    if (enabled) {
      final abilitiesNode = config.get<Map<dynamic, dynamic>>('auth.gates.abilities');
      if (abilitiesNode is Map) {
        abilitiesNode.forEach((key, value) {
          final ability = key.toString().trim();
          if (ability.isEmpty) {
            return;
          }
          final callback = _buildGateFromSpec(ability, value);
          if (callback == null) {
            return;
          }

          final managedBefore = _managedConfigGates.contains(ability);
          if (managedBefore) {
            registry.unregister(ability);
          }

          try {
            registry.register(ability, callback);
          } on GateRegistrationException {
            if (!managedBefore) {
              // Preserve user-defined gate registrations when names collide.
              return;
            }
            rethrow;
          }

          newAbilities.add(ability);
          final middlewareId = 'routed.auth.gate.$ability';
          middlewareRegistry.register(
            middlewareId,
            (_) => Haigate.middleware(
              [ability],
              deniedStatusCode: defaults.statusCode,
              deniedMessage: defaults.message,
            ),
          );
          newMiddlewareIds.add(middlewareId);
        });
      }
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

  _GateMiddlewareDefaults _resolveGateDefaults(Config config) {
    final defaultsNode = config.get<Map<dynamic, dynamic>>('auth.gates.defaults');
    var statusCode = HttpStatus.forbidden;
    String? message;

    Map<String, dynamic>? map;
    if (defaultsNode is Map) {
      map = <String, dynamic>{};
      defaultsNode.forEach((key, value) {
        map![key.toString().toLowerCase()] = value;
      });
    }

    if (map != null) {
      final statusValue = map['denied_status'] ?? map['status'] ?? map['code'];
      final parsedStatus = map.getInt('denied_status') ?? map.getInt('status') ?? map.getInt('code') ?? statusCode;
      if (parsedStatus > 0) {
        statusCode = parsedStatus;
      }

      final rawMessage = map.getString('denied_message', allowEmpty: true) ?? map.getString('message', allowEmpty: true) ?? '';
      final trimmed = rawMessage.trim();
      message = trimmed.isEmpty ? null : trimmed;
    }

    return _GateMiddlewareDefaults(statusCode: statusCode, message: message);
  }

  GateCallback? _buildGateFromSpec(String ability, dynamic spec) {
    if (spec == null) {
      return null;
    }

    var allowGuest = false;
    var any = false;
    var type = 'roles';
    List<String> roles = const <String>[];

    void assignRoles(dynamic source) {
      roles = _parseRoles(source);
    }

    if (spec is String) {
      final value = spec.trim();
      if (value.isEmpty) {
        return null;
      }
      final lower = value.toLowerCase();
      if (lower == 'authenticated' || lower == 'auth') {
        type = 'authenticated';
      } else if (lower == 'guest' || lower == 'guests') {
        type = 'guest';
      } else if (lower.startsWith('roles_any:') ||
          lower.startsWith('roles-any:')) {
        type = 'roles';
        any = true;
        assignRoles(value.substring(lower.indexOf(':') + 1));
      } else if (lower.startsWith('roles:') || lower.startsWith('role:')) {
        type = 'roles';
        assignRoles(value.substring(lower.indexOf(':') + 1));
      } else {
        type = 'roles';
        assignRoles(value);
      }
    } else if (spec is Iterable) {
      type = 'roles';
      assignRoles(spec);
    } else if (spec is Map) {
      final normalized = <String, dynamic>{};
      spec.forEach((key, value) {
        normalized[key.toString().toLowerCase()] = value;
      });

      final rawType = normalized['type']?.toString().toLowerCase();
      if (rawType != null && rawType.isNotEmpty) {
        if (rawType.contains('roles') && rawType.contains('any')) {
          type = 'roles';
          any = true;
        } else {
          type = rawType;
        }
      }

      if (normalized.containsKey('roles')) {
        assignRoles(normalized['roles']);
        type = 'roles';
      } else if (normalized.containsKey('role')) {
        assignRoles(normalized['role']);
        type = 'roles';
      }

      final mode = normalized['mode']?.toString().toLowerCase();
      if (mode == 'any') {
        any = true;
      }
      final anyFlag = normalized.getBool('any');
      if (anyFlag) {
        any = true;
      }

      allowGuest = normalized.getBool('allow_guest') ||
                   normalized.getBool('allowguests') ||
                   normalized.getBool('allowguest') ||
                   normalized.getBool('guest') ||
                   normalized.getBool('guests');
    } else {
      return null;
    }

    switch (type) {
      case 'guest':
      case 'guests':
        return (GateEvaluationContext context) => context.principal == null;
      case 'authenticated':
      case 'auth':
        return (GateEvaluationContext context) => context.principal != null;
      case 'roles':
      case 'role':
      case 'roles_any':
        final requiredRoles = roles;
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
      default:
        return null;
    }
  }

  AuthGuard? _buildGuardFromSpec(dynamic spec, SessionAuthService sessionAuth) {
    if (spec == null) {
      return null;
    }

    String? type;
    var any = false;
    final options = <String, dynamic>{};
    List<String> roles = const [];

    void assignRoles(dynamic source) {
      roles = _parseRoles(source);
    }

    if (spec is String) {
      final value = spec.trim();
      if (value.isEmpty) {
        return null;
      }
      final lower = value.toLowerCase();
      if (lower.startsWith('roles_any:')) {
        type = 'roles';
        any = true;
        assignRoles(value.substring('roles_any:'.length));
      } else if (lower.startsWith('roles-any:')) {
        type = 'roles';
        any = true;
        assignRoles(value.substring('roles-any:'.length));
      } else if (lower.startsWith('roles:')) {
        type = 'roles';
        assignRoles(value.substring('roles:'.length));
      } else if (lower.startsWith('role:')) {
        type = 'roles';
        assignRoles(value.substring('role:'.length));
      } else {
        type = lower;
      }
    } else if (spec is Map) {
      spec.forEach((key, value) {
        options[key.toString()] = value;
      });
      final rawType = options['type']?.toString().toLowerCase();
      if (rawType != null) {
        if (rawType.contains('roles') && rawType.contains('any')) {
          type = 'roles';
          any = true;
        } else {
          type = rawType;
        }
      }
      if (options.containsKey('roles')) {
        assignRoles(options['roles']);
      } else if (options.containsKey('role')) {
        assignRoles(options['role']);
      }
      final mode = options['mode']?.toString().toLowerCase();
      if (mode == 'any') {
        any = true;
      }
      final anyFlag = options['any'];
      if (anyFlag is bool && anyFlag) {
        any = true;
      }
    } else {
      return null;
    }

    if (type == null || type.isEmpty) {
      return null;
    }

    switch (type) {
      case 'authenticated':
      case 'auth':
        final realm = options['realm']?.toString();
        return requireAuthenticated(
          realm: realm == null || realm.isEmpty ? 'Restricted' : realm,
          sessionAuth: sessionAuth,
        );
      case 'roles':
      case 'role':
        if (roles.isEmpty && options.containsKey('value')) {
          assignRoles(options['value']);
        }
        if (roles.isEmpty) {
          return null;
        }
        return requireRoles(roles, sessionAuth: sessionAuth, any: any);
      default:
        return null;
    }
  }

  List<String> _parseRoles(dynamic source) {
    if (source == null) {
      return const [];
    }
    if (source is Iterable) {
      return source
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    }
    if (source is String) {
      return source
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    }
    final single = source.toString().trim();
    return single.isEmpty ? const [] : <String>[single];
  }

  FutureOr<Response> _passthrough(EngineContext ctx, Next next) => next();

  JwtVerifier? _buildJwtVerifier(Config config) {
    final enabled = config.getBool('auth.jwt.enabled');
    if (!enabled) {
      return null;
    }

    final issuer = config.getStringOrNull('auth.jwt.issuer', allowEmpty: true);

    final audience = config.getStringListOrNull('auth.jwt.audience') ?? const <String>[];

    final requiredClaims = config.getStringListOrNull('auth.jwt.required_claims') ?? const <String>[];

    final algorithms = config.getStringListOrNull('auth.jwt.algorithms') ?? const <String>['RS256'];

    final jwksUrl = config.getStringOrNull('auth.jwt.jwks_url', allowEmpty: true);
    final jwksUri = jwksUrl == null || jwksUrl.isEmpty
        ? null
        : Uri.parse(jwksUrl);

    final cacheTtl = config.getDuration('auth.jwt.jwks_cache_ttl', defaultValue: const Duration(minutes: 5));

    final clockSkew = config.getDuration('auth.jwt.clock_skew', defaultValue: const Duration(seconds: 60));

    final header = config.getString('auth.jwt.header', defaultValue: 'Authorization');

    final prefix = config.getString('auth.jwt.bearer_prefix', defaultValue: 'Bearer ');

    final keysNode = config.get<Object?>('auth.jwt.keys');
    final inlineKeys = <Map<String, dynamic>>[];
    if (keysNode is Iterable) {
      for (final entry in keysNode) {
        if (entry is Map) {
          inlineKeys.add(
            entry.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
      }
    }

    final options = JwtOptions(
      enabled: true,
      issuer: issuer?.isEmpty ?? true ? null : issuer,
      audience: audience,
      requiredClaims: requiredClaims,
      jwksUri: jwksUri,
      inlineKeys: inlineKeys,
      algorithms: algorithms.isEmpty ? const <String>['RS256'] : algorithms,
      clockSkew: clockSkew,
      jwksCacheTtl: cacheTtl,
      header: header,
      bearerPrefix: prefix,
    );

    return JwtVerifier(options: options, httpClient: _httpClient);
  }

  Middleware? _buildOAuthMiddleware(Config config) {
    final enabled = config.getBool('auth.oauth2.introspection.enabled');
    if (!enabled) {
      return null;
    }

    final endpoint = config.getString('auth.oauth2.introspection.endpoint');
    if (endpoint.isEmpty) {
      throw ProviderConfigException(
        'auth.oauth2.introspection.endpoint is required when enabled',
      );
    }

    final clientId = config.getStringOrNull('auth.oauth2.introspection.client_id', allowEmpty: true);

    final clientSecret = config.getStringOrNull('auth.oauth2.introspection.client_secret', allowEmpty: true);

    final tokenTypeHint = config.getStringOrNull('auth.oauth2.introspection.token_type_hint', allowEmpty: true);

    final cacheTtl = config.getDuration('auth.oauth2.introspection.cache_ttl', defaultValue: const Duration(seconds: 30));

    final clockSkew = config.getDuration('auth.oauth2.introspection.clock_skew', defaultValue: const Duration(seconds: 60));

    final additional = <String, String>{};
    final additionalNode = config.get<Map<dynamic, dynamic>>('auth.oauth2.introspection.additional');
    if (additionalNode is Map) {
      additionalNode.forEach((key, value) {
        if (value != null) {
          additional[key.toString()] = value.toString();
        }
      });
    }

    final options = OAuthIntrospectionOptions(
      endpoint: Uri.parse(endpoint),
      clientId: clientId?.isEmpty ?? true ? null : clientId,
      clientSecret: clientSecret?.isEmpty ?? true ? null : clientSecret,
      tokenTypeHint: tokenTypeHint?.isEmpty ?? true ? null : tokenTypeHint,
      cacheTtl: cacheTtl,
      clockSkew: clockSkew,
      additionalParameters: additional,
    );

    return oauth2Introspection(options, httpClient: _httpClient);
  }
}

class _GateMiddlewareDefaults {
  const _GateMiddlewareDefaults({
    this.statusCode = HttpStatus.forbidden,
    this.message,
  });

  final int statusCode;
  final String? message;
}
