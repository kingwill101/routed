import 'dart:io';

import 'config_utils.dart';
import 'gates.dart';
import 'guards.dart';
import 'models.dart';

const List<String> _defaultJwtAlgorithms = ['RS256'];

/// Normalized auth configuration consumed by framework adapters.
class AuthConfig {
  const AuthConfig({
    required this.jwt,
    required this.oauth2Introspection,
    required this.providers,
    required this.session,
    required this.sessionRememberMe,
    required this.callbacks,
    required this.events,
    required this.haigate,
    required this.guards,
  });

  factory AuthConfig.fromMap(Map<String, dynamic> map) {
    final jwtMap = _mapOrEmpty(map['jwt'], 'auth.jwt');
    final jwtConfig = AuthJwtConfig.fromMap(jwtMap, context: 'auth.jwt');

    final oauthMap = _mapOrEmpty(map['oauth2'], 'auth.oauth2');
    final introspectionMap = _mapOrEmpty(
      oauthMap['introspection'],
      'auth.oauth2.introspection',
    );
    final oauthConfig = OAuthIntrospectionConfig.fromMap(
      introspectionMap,
      context: 'auth.oauth2.introspection',
    );

    final providers = _mapOrEmpty(map['providers'], 'auth.providers');

    final sessionMap = _mapOrEmpty(map['session'], 'auth.session');
    final sessionConfig = AuthSessionConfig.fromMap(
      sessionMap,
      context: 'auth.session',
    );
    final rememberConfig = sessionConfig.rememberMe;

    final callbacksMap = _mapOrEmpty(map['callbacks'], 'auth.callbacks');
    final callbacks = AuthCallbackConfig.fromMap(
      callbacksMap,
      context: 'auth.callbacks',
    );

    final eventsMap = _mapOrEmpty(map['events'], 'auth.events');
    final events = AuthEventConfig.fromMap(eventsMap, context: 'auth.events');

    final featuresMap = _mapOrEmpty(map['features'], 'auth.features');
    final haigateFeature = _mapOrEmpty(
      featuresMap['haigate'],
      'auth.features.haigate',
    );
    final haigateEnabled =
        parseBoolLike(
          haigateFeature['enabled'],
          context: 'auth.features.haigate.enabled',
          throwOnInvalid: true,
        ) ??
        false;

    final gatesMap = _mapOrEmpty(map['gates'], 'auth.gates');
    final defaultsMap = _mapOrEmpty(
      gatesMap['defaults'],
      'auth.gates.defaults',
    );
    final gateDefaults = GateDefaults.fromMap(
      defaultsMap,
      context: 'auth.gates.defaults',
    );
    final abilitiesMap = _mapOrEmpty(
      gatesMap['abilities'],
      'auth.gates.abilities',
    );
    final abilities = GateDefinition.parseAbilities(
      abilitiesMap,
      context: 'auth.gates.abilities',
    );

    final guardsMap = _mapOrEmpty(map['guards'], 'auth.guards');
    final guards = GuardDefinition.parseGuards(
      guardsMap,
      context: 'auth.guards',
    );

    return AuthConfig(
      jwt: jwtConfig,
      oauth2Introspection: oauthConfig,
      providers: providers,
      session: sessionConfig,
      sessionRememberMe: rememberConfig,
      callbacks: callbacks,
      events: events,
      haigate: HaigateConfig(
        enabled: haigateEnabled,
        defaults: gateDefaults,
        abilities: abilities,
      ),
      guards: guards,
    );
  }

  final AuthJwtConfig jwt;
  final OAuthIntrospectionConfig oauth2Introspection;
  final Map<String, dynamic> providers;
  final AuthSessionConfig session;
  final SessionRememberMeConfig sessionRememberMe;
  final AuthCallbackConfig callbacks;
  final AuthEventConfig events;
  final HaigateConfig haigate;
  final Map<String, GuardDefinition> guards;
}

class AuthJwtConfig {
  const AuthJwtConfig({
    required this.enabled,
    required this.issuer,
    required this.audience,
    required this.requiredClaims,
    required this.jwksUri,
    required this.jwksCacheTtl,
    required this.clockSkew,
    required this.algorithms,
    required this.inlineKeys,
    required this.header,
    required this.bearerPrefix,
  });

  factory AuthJwtConfig.fromMap(
    Map<String, dynamic> map, {
    required String context,
  }) {
    final enabled =
        parseBoolLike(
          map['enabled'],
          context: '$context.enabled',
          throwOnInvalid: true,
        ) ??
        false;
    final issuer = parseStringLike(
      map['issuer'],
      context: '$context.issuer',
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final audience =
        parseStringList(
          map['audience'],
          context: '$context.audience',
          allowEmptyResult: true,
          coerceNonStringEntries: true,
          throwOnInvalid: true,
        ) ??
        const <String>[];
    final requiredClaims =
        parseStringList(
          map['required_claims'],
          context: '$context.required_claims',
          allowEmptyResult: true,
          coerceNonStringEntries: true,
          throwOnInvalid: true,
        ) ??
        const <String>[];
    final jwksUrl = parseStringLike(
      map['jwks_url'],
      context: '$context.jwks_url',
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final jwksUri = jwksUrl == null || jwksUrl.isEmpty
        ? null
        : Uri.parse(jwksUrl);
    final jwksCacheTtl =
        parseDurationLike(
          map['jwks_cache_ttl'],
          context: '$context.jwks_cache_ttl',
          throwOnInvalid: true,
        ) ??
        const Duration(minutes: 5);
    final clockSkew =
        parseDurationLike(
          map['clock_skew'],
          context: '$context.clock_skew',
          throwOnInvalid: true,
        ) ??
        const Duration(seconds: 60);
    final algorithms =
        parseStringList(
          map['algorithms'],
          context: '$context.algorithms',
          allowEmptyResult: true,
          coerceNonStringEntries: true,
          throwOnInvalid: true,
        ) ??
        _defaultJwtAlgorithms;
    final normalizedAlgorithms = algorithms.isEmpty
        ? _defaultJwtAlgorithms
        : algorithms;
    final inlineKeys = parseMapList(map['keys'], context: '$context.keys');
    final header =
        parseStringLike(
          map['header'],
          context: '$context.header',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        'Authorization';
    final bearerPrefix =
        parseStringLike(
          map['bearer_prefix'],
          context: '$context.bearer_prefix',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        'Bearer ';

    return AuthJwtConfig(
      enabled: enabled,
      issuer: issuer,
      audience: audience,
      requiredClaims: requiredClaims,
      jwksUri: jwksUri,
      jwksCacheTtl: jwksCacheTtl,
      clockSkew: clockSkew,
      algorithms: normalizedAlgorithms,
      inlineKeys: inlineKeys,
      header: header,
      bearerPrefix: bearerPrefix,
    );
  }

  final bool enabled;
  final String? issuer;
  final List<String> audience;
  final List<String> requiredClaims;
  final Uri? jwksUri;
  final Duration jwksCacheTtl;
  final Duration clockSkew;
  final List<String> algorithms;
  final List<Map<String, dynamic>> inlineKeys;
  final String header;
  final String bearerPrefix;
}

class OAuthIntrospectionConfig {
  const OAuthIntrospectionConfig({
    required this.enabled,
    required this.endpoint,
    required this.clientId,
    required this.clientSecret,
    required this.tokenTypeHint,
    required this.cacheTtl,
    required this.clockSkew,
    required this.additionalParameters,
  });

  factory OAuthIntrospectionConfig.fromMap(
    Map<String, dynamic> map, {
    required String context,
  }) {
    final enabled =
        parseBoolLike(
          map['enabled'],
          context: '$context.enabled',
          throwOnInvalid: true,
        ) ??
        false;
    final endpoint = parseStringLike(
      map['endpoint'],
      context: '$context.endpoint',
      allowEmpty: true,
      throwOnInvalid: true,
    );
    if (enabled && (endpoint == null || endpoint.isEmpty)) {
      throw ProviderConfigException(
        '$context.endpoint is required when enabled',
      );
    }
    final clientId = parseStringLike(
      map['client_id'],
      context: '$context.client_id',
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final clientSecret = parseStringLike(
      map['client_secret'],
      context: '$context.client_secret',
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final tokenTypeHint = parseStringLike(
      map['token_type_hint'],
      context: '$context.token_type_hint',
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final cacheTtl =
        parseDurationLike(
          map['cache_ttl'],
          context: '$context.cache_ttl',
          throwOnInvalid: true,
        ) ??
        const Duration(seconds: 30);
    final clockSkew =
        parseDurationLike(
          map['clock_skew'],
          context: '$context.clock_skew',
          throwOnInvalid: true,
        ) ??
        const Duration(seconds: 60);
    final additional = parseStringMapAllowNulls(
      map['additional'],
      context: '$context.additional',
      coerceValues: true,
      allowEmptyValues: true,
    );

    return OAuthIntrospectionConfig(
      enabled: enabled,
      endpoint: endpoint == null || endpoint.isEmpty
          ? null
          : Uri.parse(endpoint),
      clientId: clientId,
      clientSecret: clientSecret,
      tokenTypeHint: tokenTypeHint,
      cacheTtl: cacheTtl,
      clockSkew: clockSkew,
      additionalParameters: additional,
    );
  }

  final bool enabled;
  final Uri? endpoint;
  final String? clientId;
  final String? clientSecret;
  final String? tokenTypeHint;
  final Duration cacheTtl;
  final Duration clockSkew;
  final Map<String, String> additionalParameters;
}

class SessionRememberMeConfig {
  const SessionRememberMeConfig({
    required this.cookieName,
    required this.duration,
  });

  factory SessionRememberMeConfig.fromMap(
    Map<String, dynamic> map, {
    required String context,
  }) {
    final cookieName =
        parseStringLike(
          map['cookie'],
          context: '$context.cookie',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        'remember_token';
    final resolvedCookie = cookieName.trim().isEmpty
        ? 'remember_token'
        : cookieName;
    final duration =
        parseDurationLike(
          map['duration'],
          context: '$context.duration',
          throwOnInvalid: true,
        ) ??
        const Duration(days: 30);
    return SessionRememberMeConfig(
      cookieName: resolvedCookie,
      duration: duration,
    );
  }

  final String? cookieName;
  final Duration duration;
}

class AuthSessionConfig {
  const AuthSessionConfig({
    required this.strategy,
    required this.maxAge,
    required this.updateAge,
    required this.rememberMe,
  });

  factory AuthSessionConfig.fromMap(
    Map<String, dynamic> map, {
    required String context,
  }) {
    final rawStrategy = parseStringLike(
      map['strategy'],
      context: '$context.strategy',
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final normalized = rawStrategy?.trim().toLowerCase();
    final strategy = switch (normalized) {
      'session' => AuthSessionStrategy.session,
      'jwt' => AuthSessionStrategy.jwt,
      _ => null,
    };

    final maxAge = parseDurationLike(
      map['max_age'],
      context: '$context.max_age',
      throwOnInvalid: true,
    );
    final updateAge = parseDurationLike(
      map['update_age'],
      context: '$context.update_age',
      throwOnInvalid: true,
    );

    final rememberMap = _mapOrEmpty(map['remember_me'], '$context.remember_me');
    final remember = SessionRememberMeConfig.fromMap(
      rememberMap,
      context: '$context.remember_me',
    );

    return AuthSessionConfig(
      strategy: strategy,
      maxAge: maxAge,
      updateAge: updateAge,
      rememberMe: remember,
    );
  }

  final AuthSessionStrategy? strategy;
  final Duration? maxAge;
  final Duration? updateAge;
  final SessionRememberMeConfig rememberMe;
}

class AuthCallbackConfig {
  const AuthCallbackConfig({
    this.signIn,
    this.redirect,
    this.jwt,
    this.session,
  });

  factory AuthCallbackConfig.fromMap(
    Map<String, dynamic> map, {
    required String context,
  }) {
    return AuthCallbackConfig(
      signIn: parseStringLike(
        map['sign_in'],
        context: '$context.sign_in',
        allowEmpty: true,
        throwOnInvalid: true,
      ),
      redirect: parseStringLike(
        map['redirect'],
        context: '$context.redirect',
        allowEmpty: true,
        throwOnInvalid: true,
      ),
      jwt: parseStringLike(
        map['jwt'],
        context: '$context.jwt',
        allowEmpty: true,
        throwOnInvalid: true,
      ),
      session: parseStringLike(
        map['session'],
        context: '$context.session',
        allowEmpty: true,
        throwOnInvalid: true,
      ),
    );
  }

  final String? signIn;
  final String? redirect;
  final String? jwt;
  final String? session;
}

class AuthEventConfig {
  const AuthEventConfig({
    required this.signIn,
    required this.signOut,
    required this.createUser,
    required this.updateUser,
    required this.linkAccount,
    required this.session,
  });

  factory AuthEventConfig.fromMap(
    Map<String, dynamic> map, {
    required String context,
  }) {
    return AuthEventConfig(
      signIn:
          parseStringList(
            map['sign_in'],
            context: '$context.sign_in',
            allowEmptyResult: true,
            throwOnInvalid: true,
          ) ??
          const [],
      signOut:
          parseStringList(
            map['sign_out'],
            context: '$context.sign_out',
            allowEmptyResult: true,
            throwOnInvalid: true,
          ) ??
          const [],
      createUser:
          parseStringList(
            map['create_user'],
            context: '$context.create_user',
            allowEmptyResult: true,
            throwOnInvalid: true,
          ) ??
          const [],
      updateUser:
          parseStringList(
            map['update_user'],
            context: '$context.update_user',
            allowEmptyResult: true,
            throwOnInvalid: true,
          ) ??
          const [],
      linkAccount:
          parseStringList(
            map['link_account'],
            context: '$context.link_account',
            allowEmptyResult: true,
            throwOnInvalid: true,
          ) ??
          const [],
      session:
          parseStringList(
            map['session'],
            context: '$context.session',
            allowEmptyResult: true,
            throwOnInvalid: true,
          ) ??
          const [],
    );
  }

  final List<String> signIn;
  final List<String> signOut;
  final List<String> createUser;
  final List<String> updateUser;
  final List<String> linkAccount;
  final List<String> session;
}

class HaigateConfig {
  const HaigateConfig({
    required this.enabled,
    required this.defaults,
    required this.abilities,
  });

  final bool enabled;
  final GateDefaults defaults;
  final Map<String, GateDefinition> abilities;
}

class GateDefaults {
  const GateDefaults({required this.statusCode, this.message});

  factory GateDefaults.fromMap(
    Map<String, dynamic> map, {
    required String context,
  }) {
    var statusCode = HttpStatus.forbidden;
    final parsed =
        parseIntLike(
          map['denied_status'],
          context: '$context.denied_status',
          throwOnInvalid: true,
        ) ??
        parseIntLike(
          map['status'],
          context: '$context.status',
          throwOnInvalid: true,
        ) ??
        parseIntLike(
          map['code'],
          context: '$context.code',
          throwOnInvalid: true,
        );
    if (parsed != null && parsed > 0) {
      statusCode = parsed;
    }
    final rawMessage =
        parseStringLike(
          map['denied_message'],
          context: '$context.denied_message',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        parseStringLike(
          map['message'],
          context: '$context.message',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        '';
    final trimmed = rawMessage.trim();
    final message = trimmed.isEmpty ? null : trimmed;
    return GateDefaults(statusCode: statusCode, message: message);
  }

  final int statusCode;
  final String? message;
}

enum GateType { authenticated, guest, roles }

class GateDefinition {
  const GateDefinition.authenticated()
    : type = GateType.authenticated,
      roles = const [],
      any = false,
      allowGuest = false;

  const GateDefinition.guest()
    : type = GateType.guest,
      roles = const [],
      any = false,
      allowGuest = false;

  const GateDefinition.roles({
    required this.roles,
    this.any = false,
    this.allowGuest = false,
  }) : type = GateType.roles;

  final GateType type;
  final List<String> roles;
  final bool any;
  final bool allowGuest;

  static Map<String, GateDefinition> parseAbilities(
    Map<String, dynamic> map, {
    required String context,
  }) {
    if (map.isEmpty) {
      return const {};
    }
    final abilities = <String, GateDefinition>{};
    map.forEach((key, value) {
      final name = key.toString().trim();
      if (name.isEmpty) {
        return;
      }
      final definition = fromSpec(value, context: '$context.$name');
      if (definition != null) {
        abilities[name] = definition;
      }
    });
    return abilities;
  }

  static GateDefinition? fromSpec(Object? spec, {required String context}) {
    if (spec == null) {
      return null;
    }

    var allowGuest = false;
    var any = false;
    var type = 'roles';
    List<String> roles = const <String>[];

    void assignRoles(Object? source, String roleContext) {
      roles = _parseRoles(source, roleContext);
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
        assignRoles(value.substring(lower.indexOf(':') + 1), '$context.roles');
      } else if (lower.startsWith('roles:') || lower.startsWith('role:')) {
        type = 'roles';
        assignRoles(value.substring(lower.indexOf(':') + 1), '$context.roles');
      } else {
        type = 'roles';
        assignRoles(value, '$context.roles');
      }
    } else if (spec is Iterable) {
      type = 'roles';
      assignRoles(spec, '$context.roles');
    } else if (spec is Map) {
      final normalized = _normalizeMap(spec);
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
        assignRoles(normalized['roles'], '$context.roles');
        type = 'roles';
      } else if (normalized.containsKey('role')) {
        assignRoles(normalized['role'], '$context.roles');
        type = 'roles';
      }

      final mode = parseStringLike(
        normalized['mode'],
        context: '$context.mode',
        allowEmpty: true,
        throwOnInvalid: true,
      )?.toLowerCase();
      if (mode == 'any') {
        any = true;
      }
      if (parseBoolLike(
            normalized['any'],
            context: '$context.any',
            throwOnInvalid: true,
          ) ??
          false) {
        any = true;
      }

      allowGuest =
          (parseBoolLike(
                normalized['allow_guest'],
                context: '$context.allow_guest',
                throwOnInvalid: true,
              ) ??
              false) ||
          (parseBoolLike(
                normalized['allowguests'],
                context: '$context.allow_guests',
                throwOnInvalid: true,
              ) ??
              false) ||
          (parseBoolLike(
                normalized['allowguest'],
                context: '$context.allow_guest',
                throwOnInvalid: true,
              ) ??
              false) ||
          (parseBoolLike(
                normalized['guest'],
                context: '$context.guest',
                throwOnInvalid: true,
              ) ??
              false) ||
          (parseBoolLike(
                normalized['guests'],
                context: '$context.guest',
                throwOnInvalid: true,
              ) ??
              false);
    } else {
      return null;
    }

    switch (type) {
      case 'guest':
      case 'guests':
        return const GateDefinition.guest();
      case 'authenticated':
      case 'auth':
        return const GateDefinition.authenticated();
      case 'roles':
      case 'role':
      case 'roles_any':
        return GateDefinition.roles(
          roles: roles,
          any: any,
          allowGuest: allowGuest,
        );
      default:
        return null;
    }
  }

  Map<String, dynamic> toMap() {
    return switch (type) {
      GateType.authenticated => const {'type': 'authenticated'},
      GateType.guest => const {'type': 'guest'},
      GateType.roles => {
        'type': any ? 'roles_any' : 'roles',
        'roles': roles,
        if (any) 'any': true,
        if (allowGuest) 'allow_guest': true,
      },
    };
  }
}

enum GuardType { authenticated, roles }

class GuardDefinition {
  const GuardDefinition.authenticated({this.realm = 'Restricted'})
    : type = GuardType.authenticated,
      roles = const [],
      any = false;

  const GuardDefinition.roles({required this.roles, this.any = false})
    : type = GuardType.roles,
      realm = null;

  final GuardType type;
  final List<String> roles;
  final bool any;
  final String? realm;

  static Map<String, GuardDefinition> parseGuards(
    Map<String, dynamic> map, {
    required String context,
  }) {
    if (map.isEmpty) {
      return const {};
    }
    final guards = <String, GuardDefinition>{};
    map.forEach((key, value) {
      final name = key.toString().trim();
      if (name.isEmpty) {
        return;
      }
      final definition = fromSpec(value, context: '$context.$name');
      if (definition != null) {
        guards[name] = definition;
      }
    });
    return guards;
  }

  static GuardDefinition? fromSpec(Object? spec, {required String context}) {
    if (spec == null) {
      return null;
    }

    String? type;
    var any = false;
    List<String> roles = const <String>[];
    String? realm;
    final options = <String, dynamic>{};

    void assignRoles(Object? source, String roleContext) {
      roles = _parseRoles(source, roleContext);
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
        assignRoles(value.substring('roles_any:'.length), '$context.roles');
      } else if (lower.startsWith('roles-any:')) {
        type = 'roles';
        any = true;
        assignRoles(value.substring('roles-any:'.length), '$context.roles');
      } else if (lower.startsWith('roles:')) {
        type = 'roles';
        assignRoles(value.substring('roles:'.length), '$context.roles');
      } else if (lower.startsWith('role:')) {
        type = 'roles';
        assignRoles(value.substring('role:'.length), '$context.roles');
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
        assignRoles(options['roles'], '$context.roles');
      } else if (options.containsKey('role')) {
        assignRoles(options['role'], '$context.roles');
      }
      final mode = parseStringLike(
        options['mode'],
        context: '$context.mode',
        allowEmpty: true,
        throwOnInvalid: true,
      )?.toLowerCase();
      if (mode == 'any') {
        any = true;
      }
      if (parseBoolLike(
            options['any'],
            context: '$context.any',
            throwOnInvalid: true,
          ) ??
          false) {
        any = true;
      }
      realm = parseStringLike(
        options['realm'],
        context: '$context.realm',
        allowEmpty: true,
        throwOnInvalid: true,
      );
    } else {
      return null;
    }

    if (type == null || type.isEmpty) {
      return null;
    }

    switch (type) {
      case 'authenticated':
      case 'auth':
        final resolvedRealm = realm == null || realm.trim().isEmpty
            ? 'Restricted'
            : realm.trim();
        return GuardDefinition.authenticated(realm: resolvedRealm);
      case 'roles':
      case 'role':
        if (roles.isEmpty && options.containsKey('value')) {
          assignRoles(options['value'], '$context.roles');
        }
        if (roles.isEmpty) {
          return null;
        }
        return GuardDefinition.roles(roles: roles, any: any);
      default:
        return null;
    }
  }

  Map<String, dynamic> toMap() {
    return switch (type) {
      GuardType.authenticated => {
        'type': 'authenticated',
        if (realm != null) 'realm': realm,
      },
      GuardType.roles => {
        'type': any ? 'roles_any' : 'roles',
        'roles': roles,
        if (any) 'any': true,
      },
    };
  }
}

/// Resolves a generic auth gate callback from [definition].
AuthGateCallback<TContext>? resolveConfiguredGateCallback<TContext>(
  GateDefinition definition,
) {
  switch (definition.type) {
    case GateType.guest:
      return guestGate<TContext>();
    case GateType.authenticated:
      return authenticatedGate<TContext>();
    case GateType.roles:
      return rolesGate<TContext>(
        definition.roles,
        any: definition.any,
        allowGuest: definition.allowGuest,
      );
  }
}

/// Resolves a generic auth guard from [definition].
AuthGuard<TContext, TResponse>? resolveConfiguredGuard<TContext, TResponse>({
  required GuardDefinition definition,
  required AuthGuard<TContext, TResponse> Function(String realm)
  authenticatedGuard,
  required AuthGuard<TContext, TResponse> Function(List<String> roles, bool any)
  rolesGuard,
}) {
  switch (definition.type) {
    case GuardType.authenticated:
      final realm = definition.realm == null || definition.realm!.trim().isEmpty
          ? 'Restricted'
          : definition.realm!;
      return authenticatedGuard(realm);
    case GuardType.roles:
      if (definition.roles.isEmpty) {
        return null;
      }
      return rolesGuard(definition.roles, definition.any);
  }
}

Map<String, dynamic> _mapOrEmpty(Object? value, String context) {
  if (value == null) {
    return const <String, dynamic>{};
  }
  return stringKeyedMap(value, context);
}

Map<String, dynamic> _normalizeMap(Map<Object?, Object?> map) {
  final normalized = <String, dynamic>{};
  map.forEach((key, value) {
    normalized[key.toString().toLowerCase()] = value;
  });
  return normalized;
}

List<String> _parseRoles(Object? source, String context) {
  final parsed = parseStringList(
    source,
    context: context,
    allowEmptyResult: true,
    coerceNonStringEntries: true,
    throwOnInvalid: true,
  );
  return parsed ?? const <String>[];
}
