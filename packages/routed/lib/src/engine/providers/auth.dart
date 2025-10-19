import 'dart:async';

import 'package:http/http.dart' as http;
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

  @override
  ConfigDefaults get defaultConfig => const ConfigDefaults(
    values: {
      'http': {
        'middleware_sources': {
          'routed.auth': {
            'global': ['routed.auth.jwt', 'routed.auth.oauth2'],
          },
        },
      },
    },
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
        path: 'auth.guards',
        type: 'map',
        description:
            'Named guard definitions consumed by guard middleware (e.g. authenticated, roles).',
        defaultValue: {
          'authenticated': {'type': 'authenticated', 'realm': 'Restricted'},
        },
      ),
      ConfigDocEntry(
        path: 'http.features.auth.enabled',
        type: 'bool',
        description: 'Toggle registration of authentication middleware.',
        defaultValue: false,
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

    final registry = container.get<MiddlewareRegistry>();
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
  }

  SessionAuthService _configureSessionAuth(Container container, Config config) {
    final cookieName =
        parseStringLike(
          config.get('auth.session.remember_me.cookie'),
          context: 'auth.session.remember_me.cookie',
          allowEmpty: true,
          throwOnInvalid: false,
        ) ??
        '';

    final rememberDuration = parseDurationLike(
      config.get('auth.session.remember_me.duration'),
      context: 'auth.session.remember_me.duration',
    );

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
    final node = config.get('auth.guards');
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
    final enabled =
        parseBoolLike(
          config.get('auth.jwt.enabled'),
          context: 'auth.jwt.enabled',
          stringMappings: const {'true': true, 'false': false},
        ) ??
        false;
    if (!enabled) {
      return null;
    }

    final issuer = parseStringLike(
      config.get('auth.jwt.issuer'),
      context: 'auth.jwt.issuer',
      allowEmpty: true,
      throwOnInvalid: false,
    );

    final audience =
        parseStringList(
          config.get('auth.jwt.audience'),
          context: 'auth.jwt.audience',
          allowEmptyResult: true,
        ) ??
        const <String>[];

    final requiredClaims =
        parseStringList(
          config.get('auth.jwt.required_claims'),
          context: 'auth.jwt.required_claims',
          allowEmptyResult: true,
        ) ??
        const <String>[];

    final algorithms =
        parseStringList(
          config.get('auth.jwt.algorithms'),
          context: 'auth.jwt.algorithms',
          allowEmptyResult: true,
        ) ??
        const <String>['RS256'];

    final jwksUrl = parseStringLike(
      config.get('auth.jwt.jwks_url'),
      context: 'auth.jwt.jwks_url',
      allowEmpty: true,
      throwOnInvalid: false,
    );
    final jwksUri = jwksUrl == null || jwksUrl.isEmpty
        ? null
        : Uri.parse(jwksUrl);

    final cacheTtl =
        parseDurationLike(
          config.get('auth.jwt.jwks_cache_ttl'),
          context: 'auth.jwt.jwks_cache_ttl',
        ) ??
        const Duration(minutes: 5);

    final clockSkew =
        parseDurationLike(
          config.get('auth.jwt.clock_skew'),
          context: 'auth.jwt.clock_skew',
        ) ??
        const Duration(seconds: 60);

    final header =
        parseStringLike(
          config.get('auth.jwt.header'),
          context: 'auth.jwt.header',
          allowEmpty: false,
        ) ??
        'Authorization';

    final prefix =
        parseStringLike(
          config.get('auth.jwt.bearer_prefix'),
          context: 'auth.jwt.bearer_prefix',
          allowEmpty: false,
        ) ??
        'Bearer ';

    final keysNode = config.get('auth.jwt.keys');
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
    final enabled =
        parseBoolLike(
          config.get('auth.oauth2.introspection.enabled'),
          context: 'auth.oauth2.introspection.enabled',
          stringMappings: const {'true': true, 'false': false},
        ) ??
        false;
    if (!enabled) {
      return null;
    }

    final endpoint = parseStringLike(
      config.get('auth.oauth2.introspection.endpoint'),
      context: 'auth.oauth2.introspection.endpoint',
      allowEmpty: false,
    );
    if (endpoint == null || endpoint.isEmpty) {
      throw ProviderConfigException(
        'auth.oauth2.introspection.endpoint is required when enabled',
      );
    }

    final clientId = parseStringLike(
      config.get('auth.oauth2.introspection.client_id'),
      context: 'auth.oauth2.introspection.client_id',
      allowEmpty: true,
      throwOnInvalid: false,
    );

    final clientSecret = parseStringLike(
      config.get('auth.oauth2.introspection.client_secret'),
      context: 'auth.oauth2.introspection.client_secret',
      allowEmpty: true,
      throwOnInvalid: false,
    );

    final tokenTypeHint = parseStringLike(
      config.get('auth.oauth2.introspection.token_type_hint'),
      context: 'auth.oauth2.introspection.token_type_hint',
      allowEmpty: true,
      throwOnInvalid: false,
    );

    final cacheTtl =
        parseDurationLike(
          config.get('auth.oauth2.introspection.cache_ttl'),
          context: 'auth.oauth2.introspection.cache_ttl',
        ) ??
        const Duration(seconds: 30);

    final additional = <String, String>{};
    final additionalNode = config.get('auth.oauth2.introspection.additional');
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
      additionalParameters: additional,
    );

    return oauth2Introspection(options, httpClient: _httpClient);
  }
}
