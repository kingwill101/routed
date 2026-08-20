import 'package:server_auth/server_auth.dart';

import '../openapi/openapi_spec.dart';

bool _hasJsonRequestBody(AuthOperationMethod method) => switch (method) {
  AuthOperationMethod.post ||
  AuthOperationMethod.put ||
  AuthOperationMethod.patch => true,
  AuthOperationMethod.get || AuthOperationMethod.delete => false,
};

/// Transport advertised for session-authenticated plugin operations.
///
/// Combined values are OpenAPI security alternatives (logical OR), not a
/// requirement to send every credential. API-key alternatives should only be
/// selected when the host actually authenticates these operations with an API
/// key or an API-key-to-session boundary.
enum AuthOpenApiSessionSecurity {
  cookie,
  bearer,
  cookieOrBearer,
  apiKey,
  cookieOrApiKey,
  bearerOrApiKey,
  cookieOrBearerOrApiKey,
}

/// OpenAPI generation settings for a composed auth plugin registry.
final class AuthPluginOpenApiConfig {
  const AuthPluginOpenApiConfig({
    this.basePath = '/auth',
    this.includeServerOnly = false,
    this.sessionSecurity = AuthOpenApiSessionSecurity.cookieOrBearer,
    this.sessionCookieName = 'routed_session',
    this.csrfHeaderName = 'x-csrf-token',
    this.apiKeyHeaderName = 'x-api-key',
    this.operationIdPrefix = 'auth',
  });

  /// Prefix applied to plugin-relative endpoint paths.
  final String basePath;

  /// Includes endpoints intentionally omitted from public auth clients.
  final bool includeServerOnly;

  /// Security alternatives used for session-authenticated operations.
  final AuthOpenApiSessionSecurity sessionSecurity;

  /// Cookie name advertised by the session-cookie security scheme.
  final String sessionCookieName;

  /// Header emitted for endpoints whose descriptor requires CSRF validation.
  final String csrfHeaderName;

  /// Header used by the public Routed API-key authentication boundary.
  final String apiKeyHeaderName;

  /// Prefix used for stable, generated-client-safe operation IDs.
  final String operationIdPrefix;
}

/// A composition error that would make generated auth clients ambiguous.
final class AuthOpenApiContractException implements Exception {
  const AuthOpenApiContractException(this.message);

  final String message;

  @override
  String toString() => 'AuthOpenApiContractException: $message';
}

/// Generates an OpenAPI 3.1 document from a frozen auth plugin registry.
///
/// The registry's endpoint descriptors are the route source of truth. Adding
/// or removing a plugin therefore changes the generated contract without a
/// separate route catalogue.
final class AuthPluginOpenApiGenerator<TContext> {
  const AuthPluginOpenApiGenerator({
    this.config = const AuthPluginOpenApiConfig(),
  });

  static const String sessionCookieSecurityScheme = 'authSessionCookie';
  static const String bearerSecurityScheme = 'authBearer';
  static const String apiKeySecurityScheme = 'authApiKey';

  /// Standard OpenAPI operation extensions emitted by this generator.
  static const String pluginExtension = 'x-routed-auth-plugin';
  static const String originPolicyExtension = 'x-routed-auth-origin-policy';
  static const String csrfPolicyExtension = 'x-routed-auth-csrf-policy';
  static const String rateLimitOperationExtension =
      'x-routed-auth-rate-limit-operation';
  static const String operationSemanticsExtension =
      'x-routed-auth-operation-semantics';
  static const String captchaExtension = 'x-routed-auth-captcha';
  static const String breachedPasswordExtension =
      'x-routed-auth-breached-password';

  static const String genericErrorSchema = 'AuthError';
  static const String twoFactorChallengeSchema = 'AuthTwoFactorChallenge';

  final AuthPluginOpenApiConfig config;

  OpenApiSpec generate({
    required AuthServerPluginRegistry<TContext> registry,
    required OpenApiInfo info,
    List<OpenApiServer> servers = const <OpenApiServer>[],
  }) {
    if (!registry.isFrozen) {
      throw const AuthOpenApiContractException(
        'The auth plugin registry must be frozen before generation.',
      );
    }
    if (config.operationIdPrefix.trim().isEmpty) {
      throw const AuthOpenApiContractException(
        'operationIdPrefix must not be empty.',
      );
    }

    final paths = <String, OpenApiPathItem>{};
    final schemas = <String, Map<String, Object?>>{};
    final operationIds = <String, String>{};
    final routeKeys = <String>{};
    final pluginIds = <String>{};
    var requiresSession = false;
    var requiresBearer = false;
    var hasTwoFactorChallenge = false;

    final captchaPlugin = registry.find(authCaptchaPluginId);
    final breachedPasswordPlugin = registry.find(authBreachedPasswordPluginId);
    final twoFactorPlugin = registry.find(authTwoFactorPluginId);
    final hasApiKeyPlugin = registry.find(authApiKeyPluginId) != null;
    final captchaConfig = captchaPlugin is CaptchaPlugin<TContext>
        ? captchaPlugin.config
        : null;
    final breachedPasswordConfig =
        breachedPasswordPlugin is BreachedPasswordPlugin<TContext>
        ? breachedPasswordPlugin.config
        : null;

    for (final endpoint in registry.publicEndpoints) {
      if (endpoint.serverOnly && !config.includeServerOnly) continue;

      final path = _resolvePath(endpoint.path, endpoint.mount);
      final method = endpoint.method.name.toUpperCase();
      final routeKey = '$method $path';
      if (!routeKeys.add(routeKey)) {
        throw AuthOpenApiContractException('Duplicate auth route "$routeKey".');
      }

      final operationId = _operationId(endpoint.id);
      final previousEndpoint = operationIds[operationId];
      if (previousEndpoint != null) {
        throw AuthOpenApiContractException(
          'Auth endpoints "$previousEndpoint" and "${endpoint.id}" map to '
          'the same operationId "$operationId".',
        );
      }
      operationIds[operationId] = endpoint.id;

      final pluginId =
          registry.pluginIdForEndpoint(endpoint.id) ?? _pluginId(endpoint.id);
      pluginIds.add(pluginId);

      final contracts = _contracts(endpoint);
      final requestSchemaName = '${_upperFirst(operationId)}Request';
      final responseSchemaName = '${_upperFirst(operationId)}Response';
      final request = _requestSchemaWithPolicyEffects(
        endpoint: endpoint,
        schema: contracts.request.schema,
        captchaPlugin: captchaPlugin,
        captchaConfig: captchaConfig,
        breachedPasswordPlugin: breachedPasswordPlugin,
        breachedPasswordConfig: breachedPasswordConfig,
      );
      final pathParameters = _pathParameters(
        endpoint.path,
        contracts.request.schema,
      );
      final requestSchema = _withoutPathProperties(
        request.schema,
        endpoint.path.parameters,
      );
      schemas[requestSchemaName] = requestSchema;
      schemas[responseSchemaName] = _publicResponseSchema(
        contracts.response.schema,
      );

      final hasChallengeAlternative =
          twoFactorPlugin is TwoFactorPlugin<TContext> &&
          _isSignInEndpoint(endpoint.id) &&
          _isAuthenticationResponse(contracts.response.schema) &&
          !_containsSchemaConst(
            contracts.response.schema,
            'two_factor_required',
          );
      hasTwoFactorChallenge |= hasChallengeAlternative;

      final parameters = <OpenApiParameter>[
        ...pathParameters,
        if (endpoint.method == AuthOperationMethod.get)
          ..._queryParameters(requestSchema, pathParameters),
        if (endpoint.originPolicy == AuthOperationOriginPolicy.browser)
          const OpenApiParameter(
            name: 'Origin',
            location: 'header',
            description:
                'Browser origin checked by the auth adapter when present; '
                'the deployment may require it.',
            required: false,
            schema: <String, Object?>{
              'type': 'string',
              'format': 'uri-reference',
            },
          ),
        if (endpoint.csrfPolicy == AuthOperationCsrfPolicy.required)
          OpenApiParameter(
            name: config.csrfHeaderName,
            location: 'header',
            description: 'CSRF token required by this auth operation.',
            required: true,
            schema: const <String, Object?>{'type': 'string'},
          ),
      ];

      final sessionRequired =
          endpoint.authentication == AuthOperationAuthentication.session;
      final apiKeyRequired =
          endpoint.authentication == AuthOperationAuthentication.apiKey;
      final bearerRequired =
          endpoint.authentication == AuthOperationAuthentication.bearer;
      requiresSession |= sessionRequired;
      requiresBearer |= bearerRequired;
      final explicitResponseContracts = switch (endpoint) {
        AuthEndpointResponseContractDescriptor(:final responseContracts) =>
          responseContracts.toList(growable: false),
        _ => const <AuthEndpointResponseContract>[],
      };
      final defaultResponses = <String, OpenApiResponse>{
        '200': OpenApiResponse(
          description: 'Successful response.',
          content: <String, OpenApiMediaType>{
            contracts.response.contentType: OpenApiMediaType(
              schema: <String, Object?>{
                r'$ref': '#/components/schemas/$responseSchemaName',
              },
            ),
          },
        ),
        '400': _genericErrorResponse('Invalid auth request.'),
        '401': _genericErrorResponse('Authentication failed or is required.'),
        if (endpoint.originPolicy == AuthOperationOriginPolicy.browser ||
            endpoint.csrfPolicy == AuthOperationCsrfPolicy.required)
          '403': _genericErrorResponse(
            endpoint.csrfPolicy == AuthOperationCsrfPolicy.required
                ? 'Browser origin or CSRF validation failed.'
                : 'Browser origin validation failed.',
          ),
        if (endpoint.rateLimitOperation != null)
          '429': _genericErrorResponse(
            'Auth rate limit exceeded.',
            headers: const <String, Object?>{
              'Retry-After': <String, Object?>{
                'description': 'Seconds until another request may be made.',
                'schema': <String, Object?>{'type': 'integer', 'minimum': 1},
              },
            },
          ),
        if (hasChallengeAlternative)
          '202': const OpenApiResponse(
            description: 'Additional two-factor verification is required.',
            content: <String, OpenApiMediaType>{
              'application/json': OpenApiMediaType(
                schema: <String, Object?>{
                  r'$ref': '#/components/schemas/$twoFactorChallengeSchema',
                },
              ),
            },
          ),
      };
      final responses = explicitResponseContracts.isEmpty
          ? defaultResponses
          : <String, OpenApiResponse>{
              for (final response in explicitResponseContracts)
                response.statusCode.toString(): OpenApiResponse(
                  description: response.description,
                  content: response.contract == null
                      ? null
                      : <String, OpenApiMediaType>{
                          response.contract!.contentType: OpenApiMediaType(
                            schema: Map<String, Object?>.from(
                              response.contract!.schema,
                            ),
                          ),
                        },
                ),
            };

      final extensions = <String, Object?>{
        pluginExtension: pluginId,
        originPolicyExtension: endpoint.originPolicy.name,
        csrfPolicyExtension: endpoint.csrfPolicy.name,
        operationSemanticsExtension: _operationSemantics(endpoint.semantics),
        if (endpoint.rateLimitOperation case final rateLimit?)
          rateLimitOperationExtension: <String, Object?>{
            'id': rateLimit.id,
            'namespace': rateLimit.namespace,
            'name': rateLimit.name,
          },
        ...request.policyExtensions,
      };
      final operation = OpenApiOperation(
        summary: _summary(endpoint.id),
        description: _operationDescription(
          endpoint: endpoint,
          policyExtensions: request.policyExtensions,
        ),
        operationId: operationId,
        tags: <String>[pluginId],
        parameters: parameters,
        requestBody: _hasJsonRequestBody(endpoint.method)
            ? OpenApiRequestBody(
                required: contracts.request.required,
                description: request.policyExtensions.isEmpty
                    ? null
                    : 'This request is subject to the auth policies '
                          'advertised by the operation extensions.',
                content: <String, OpenApiMediaType>{
                  contracts.request.contentType: OpenApiMediaType(
                    schema: <String, Object?>{
                      r'$ref': '#/components/schemas/$requestSchemaName',
                    },
                  ),
                },
              )
            : null,
        responses: responses,
        security: sessionRequired
            ? _sessionSecurity()
            : apiKeyRequired
            ? const <Map<String, List<String>>>[
                <String, List<String>>{apiKeySecurityScheme: <String>[]},
              ]
            : bearerRequired
            ? const <Map<String, List<String>>>[
                <String, List<String>>{bearerSecurityScheme: <String>[]},
              ]
            : const [],
        extensions: extensions,
      );

      final existing = paths[path] ?? const OpenApiPathItem();
      if (existing.operationFor(method) != null) {
        throw AuthOpenApiContractException('Duplicate auth route "$routeKey".');
      }
      paths[path] = existing.withOperation(method, operation);
    }

    if (hasTwoFactorChallenge) {
      schemas[twoFactorChallengeSchema] = _twoFactorChallengeSchema;
    }
    if (paths.isNotEmpty) {
      schemas[genericErrorSchema] = _genericErrorSchema;
    }

    return OpenApiSpec(
      info: info,
      servers: servers,
      paths: paths,
      tags: pluginIds
          .map(
            (pluginId) => OpenApiTag(
              name: pluginId,
              description: 'Authentication endpoints from $pluginId.',
            ),
          )
          .toList(growable: false),
      components: OpenApiComponents(
        schemas: schemas,
        securitySchemes: requiresSession || requiresBearer || hasApiKeyPlugin
            ? _securitySchemes(
                hasApiKeyPlugin: hasApiKeyPlugin,
                forceBearer: requiresBearer,
              )
            : const {},
      ),
    );
  }

  Map<String, Object?> _operationSemantics(AuthOperationSemantics semantics) {
    if (semantics is AuthReadOnlyOperationSemantics) {
      return const <String, Object?>{'effect': 'readOnly'};
    }
    final mutation = semantics as AuthMutationOperationSemantics;
    final persistence = mutation.persistence;
    final reference = persistence.reference;
    return <String, Object?>{
      'effect': 'mutation',
      'persistence': persistence.kind.name,
      'atomicity': persistence.atomicity.name,
      'replaySafety': mutation.replaySafety.name,
      if (reference != null)
        'persistenceReference': <String, Object?>{
          'schemaId': reference.schemaId,
          'atomicOperationId': ?reference.atomicOperationId,
        },
    };
  }

  String _resolvePath(AuthRoutePath route, AuthEndpointMount mount) {
    final endpoint = route.validate();
    if (mount == AuthEndpointMount.root) return endpoint;
    final base = _normalizePath(config.basePath);
    if (base == '/') return endpoint;
    return '$base${endpoint == '/' ? '' : endpoint}';
  }

  String _operationId(String endpointId) {
    final parts = <String>[
      ..._identifierParts(config.operationIdPrefix),
      ..._identifierParts(endpointId),
    ];
    if (parts.isEmpty) {
      throw AuthOpenApiContractException(
        'Endpoint "$endpointId" cannot produce an operationId.',
      );
    }
    return '${parts.first.toLowerCase()}'
        '${parts.skip(1).map(_upperFirst).join()}';
  }

  List<Map<String, List<String>>> _sessionSecurity() {
    switch (config.sessionSecurity) {
      case AuthOpenApiSessionSecurity.cookie:
        return const <Map<String, List<String>>>[
          <String, List<String>>{sessionCookieSecurityScheme: <String>[]},
        ];
      case AuthOpenApiSessionSecurity.bearer:
        return const <Map<String, List<String>>>[
          <String, List<String>>{bearerSecurityScheme: <String>[]},
        ];
      case AuthOpenApiSessionSecurity.cookieOrBearer:
        return const <Map<String, List<String>>>[
          <String, List<String>>{sessionCookieSecurityScheme: <String>[]},
          <String, List<String>>{bearerSecurityScheme: <String>[]},
        ];
      case AuthOpenApiSessionSecurity.apiKey:
        return const <Map<String, List<String>>>[
          <String, List<String>>{apiKeySecurityScheme: <String>[]},
        ];
      case AuthOpenApiSessionSecurity.cookieOrApiKey:
        return const <Map<String, List<String>>>[
          <String, List<String>>{sessionCookieSecurityScheme: <String>[]},
          <String, List<String>>{apiKeySecurityScheme: <String>[]},
        ];
      case AuthOpenApiSessionSecurity.bearerOrApiKey:
        return const <Map<String, List<String>>>[
          <String, List<String>>{bearerSecurityScheme: <String>[]},
          <String, List<String>>{apiKeySecurityScheme: <String>[]},
        ];
      case AuthOpenApiSessionSecurity.cookieOrBearerOrApiKey:
        return const <Map<String, List<String>>>[
          <String, List<String>>{sessionCookieSecurityScheme: <String>[]},
          <String, List<String>>{bearerSecurityScheme: <String>[]},
          <String, List<String>>{apiKeySecurityScheme: <String>[]},
        ];
    }
  }

  Map<String, OpenApiSecurityScheme> _securitySchemes({
    required bool hasApiKeyPlugin,
    bool forceBearer = false,
  }) {
    final schemes = <String, OpenApiSecurityScheme>{};
    final sessionSecurity = config.sessionSecurity;
    if (sessionSecurity != AuthOpenApiSessionSecurity.bearer &&
        sessionSecurity != AuthOpenApiSessionSecurity.apiKey &&
        sessionSecurity != AuthOpenApiSessionSecurity.bearerOrApiKey) {
      schemes[sessionCookieSecurityScheme] = OpenApiSecurityScheme(
        type: 'apiKey',
        name: config.sessionCookieName,
        location: 'cookie',
        description: 'Routed auth session cookie.',
      );
    }
    if (forceBearer ||
        sessionSecurity != AuthOpenApiSessionSecurity.cookie &&
            sessionSecurity != AuthOpenApiSessionSecurity.apiKey &&
            sessionSecurity != AuthOpenApiSessionSecurity.cookieOrApiKey) {
      schemes[bearerSecurityScheme] = const OpenApiSecurityScheme(
        type: 'http',
        scheme: 'bearer',
        description: 'Bearer token accepted by the selected auth plugin.',
      );
    }
    final hasApiKeySecurity =
        hasApiKeyPlugin ||
        sessionSecurity == AuthOpenApiSessionSecurity.apiKey ||
        sessionSecurity == AuthOpenApiSessionSecurity.cookieOrApiKey ||
        sessionSecurity == AuthOpenApiSessionSecurity.bearerOrApiKey ||
        sessionSecurity == AuthOpenApiSessionSecurity.cookieOrBearerOrApiKey;
    if (hasApiKeySecurity) {
      schemes[apiKeySecurityScheme] = OpenApiSecurityScheme(
        type: 'apiKey',
        name: config.apiKeyHeaderName,
        location: 'header',
        description:
            'Routed API key for service-authenticated application '
            'requests. Auth management endpoints use the alternatives '
            'listed on the operation.',
      );
    }
    return schemes;
  }

  ({Map<String, Object?> schema, Map<String, Object?> policyExtensions})
  _requestSchemaWithPolicyEffects({
    required AuthEndpointDescriptor<TContext> endpoint,
    required Map<String, Object?> schema,
    required AuthServerPlugin<TContext>? captchaPlugin,
    required AuthCaptchaPluginConfig? captchaConfig,
    required AuthServerPlugin<TContext>? breachedPasswordPlugin,
    required AuthBreachedPasswordPluginConfig? breachedPasswordConfig,
  }) {
    final result = _cloneSchema(schema);
    final properties = _mutableSchemaProperties(result);
    final effects = <String, Object?>{};

    if (captchaPlugin != null && properties.containsKey('captchaToken')) {
      final tokenSchema = properties['captchaToken']!;
      if (captchaConfig != null) {
        _tightenMaximum(tokenSchema, 'maxLength', captchaConfig.maxTokenLength);
      }
      _requireProperty(result, 'captchaToken');
      effects[captchaExtension] = <String, Object?>{
        'required': true,
        if (captchaConfig != null)
          'maxTokenLength': captchaConfig.maxTokenLength,
      };
    }

    final registration = _isRegistrationEndpoint(endpoint.id);
    if (breachedPasswordPlugin != null &&
        registration &&
        properties.containsKey('password')) {
      if (breachedPasswordConfig != null) {
        _tightenMaximum(
          properties['password']!,
          'maxLength',
          breachedPasswordConfig.maxPasswordLength,
        );
      }
      effects[breachedPasswordExtension] = <String, Object?>{
        'operation': 'registration',
        if (breachedPasswordConfig != null)
          'maxPasswordLength': breachedPasswordConfig.maxPasswordLength,
        'error': authBreachedPasswordRejectedErrorCode,
      };
    }

    return (schema: result, policyExtensions: effects);
  }

  String? _operationDescription({
    required AuthEndpointDescriptor<TContext> endpoint,
    required Map<String, Object?> policyExtensions,
  }) {
    final descriptions = <String>[];
    if (endpoint.originPolicy == AuthOperationOriginPolicy.browser) {
      descriptions.add(
        'The auth adapter applies browser Origin and Fetch Metadata '
        'validation for this operation.',
      );
    }
    if (endpoint.csrfPolicy == AuthOperationCsrfPolicy.required) {
      descriptions.add(
        'The auth adapter requires the documented CSRF header before '
        'invoking this operation.',
      );
    }
    if (policyExtensions.containsKey(captchaExtension)) {
      descriptions.add(
        'A registered captcha policy must accept the request token before '
        'credential processing.',
      );
    }
    if (policyExtensions.containsKey(breachedPasswordExtension)) {
      descriptions.add(
        'A registered breached-password policy may reject the password '
        'with the generic password_rejected error.',
      );
    }
    return descriptions.isEmpty ? null : descriptions.join(' ');
  }
}

const Map<String, Object?> _genericErrorSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['error'],
  'properties': <String, Object?>{
    'error': <String, Object?>{
      'type': 'string',
      'pattern': r'^[a-z][a-z0-9_]{0,63}$',
      'description': 'Sanitized, stable auth error code.',
    },
  },
};

const Map<String, Object?> _twoFactorChallengeSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['status', 'challengeToken', 'expiresAt'],
  'properties': <String, Object?>{
    'status': <String, Object?>{'const': 'two_factor_required'},
    'challengeToken': <String, Object?>{
      'type': 'string',
      'readOnly': true,
      'description': 'Short-lived token submitted to complete the challenge.',
    },
    'expiresAt': <String, Object?>{'type': 'string', 'format': 'date-time'},
  },
};

OpenApiResponse _genericErrorResponse(
  String description, {
  Map<String, Object?>? headers,
}) => OpenApiResponse(
  description: description,
  content: const <String, OpenApiMediaType>{
    'application/json': OpenApiMediaType(
      schema: <String, Object?>{r'$ref': '#/components/schemas/AuthError'},
    ),
  },
  headers: headers,
);

Map<String, Object?> _cloneSchema(Map<String, Object?> schema) {
  final cloned = _cloneJsonValue(schema);
  return Map<String, Object?>.from(cloned as Map);
}

Map<String, Object?> _publicResponseSchema(Map<String, Object?> schema) =>
    schema.isEmpty
    ? <String, Object?>{
        'type': 'object',
        'description':
            'Public JSON response. The selected plugin owns its additional '
            'fields.',
        'additionalProperties': true,
      }
    : Map<String, Object?>.from(schema);

Object? _cloneJsonValue(Object? value) {
  if (value is Map) {
    return value.map(
      (key, child) => MapEntry(key.toString(), _cloneJsonValue(child)),
    );
  }
  if (value is List) {
    return value.map(_cloneJsonValue).toList(growable: false);
  }
  return value;
}

Map<String, Map<String, Object?>> _mutableSchemaProperties(
  Map<String, Object?> schema,
) {
  final raw = schema['properties'];
  if (raw is! Map) return <String, Map<String, Object?>>{};
  final properties = <String, Map<String, Object?>>{};
  for (final entry in raw.entries) {
    properties[entry.key.toString()] = entry.value is Map
        ? Map<String, Object?>.from(entry.value as Map)
        : <String, Object?>{};
  }
  schema['properties'] = properties;
  return properties;
}

void _requireProperty(Map<String, Object?> schema, String name) {
  final required = <String>{
    if (schema['required'] is List)
      ...(schema['required'] as List).whereType<String>(),
  };
  required.add(name);
  schema['required'] = required.toList(growable: false);
}

void _tightenMaximum(Map<String, Object?> schema, String keyword, int maximum) {
  final existing = schema[keyword];
  if (existing is num && existing < maximum) return;
  schema[keyword] = maximum;
}

bool _isRegistrationEndpoint(String endpointId) {
  final normalized = endpointId.toLowerCase();
  return normalized.contains('register') || normalized.contains('registration');
}

bool _isSignInEndpoint(String endpointId) {
  final normalized = endpointId.toLowerCase();
  return normalized.contains('signin') ||
      normalized.contains('sign_in') ||
      normalized.contains('sign-in');
}

bool _isAuthenticationResponse(Map<String, Object?> schema) {
  final properties = _schemaProperties(schema);
  final status = properties['status'];
  return status?['const'] == 'authenticated';
}

bool _containsSchemaConst(Map<String, Object?> schema, Object expected) {
  bool visit(Object? value) {
    if (value is Map) {
      if (value['const'] == expected) return true;
      return value.values.any(visit);
    }
    if (value is Iterable) return value.any(visit);
    return false;
  }

  return visit(schema);
}

/// Generates an OpenAPI 3.1 document for this composed plugin registry.
extension AuthServerPluginRegistryOpenApi<TContext>
    on AuthServerPluginRegistry<TContext> {
  OpenApiSpec toOpenApi31({
    required OpenApiInfo info,
    AuthPluginOpenApiConfig config = const AuthPluginOpenApiConfig(),
    List<OpenApiServer> servers = const <OpenApiServer>[],
  }) => AuthPluginOpenApiGenerator<TContext>(
    config: config,
  ).generate(registry: this, info: info, servers: servers);
}

({AuthOperationContract request, AuthOperationContract response})
_contracts<TContext>(AuthEndpointDescriptor<TContext> endpoint) {
  if (endpoint case AuthEndpointContractDescriptor(
    requestCodec: final request,
    responseCodec: final response,
  )) {
    return (request: request, response: response);
  }
  return const (
    request: _DefaultAuthOperationContract(),
    response: _DefaultAuthOperationContract(),
  );
}

final class _DefaultAuthOperationContract implements AuthOperationContract {
  const _DefaultAuthOperationContract();

  @override
  String get contentType => 'application/json';

  @override
  bool get required => false;

  @override
  Map<String, Object?> get schema => const <String, Object?>{};
}

List<OpenApiParameter> _pathParameters(
  AuthRoutePath path,
  Map<String, Object?> schema,
) {
  final properties = _schemaProperties(schema);
  return path.parameters
      .map((parameter) => parameter.name)
      .map(
        (name) => OpenApiParameter(
          name: name,
          location: 'path',
          required: true,
          schema: properties[name] ?? const <String, Object?>{'type': 'string'},
        ),
      )
      .toList(growable: false);
}

Map<String, Object?> _withoutPathProperties(
  Map<String, Object?> schema,
  Iterable<AuthRouteParameterKey> parameters,
) {
  final names = parameters.map((parameter) => parameter.name).toSet();
  if (names.isEmpty) return Map<String, Object?>.from(schema);
  final result = Map<String, Object?>.from(schema);
  if (schema['properties'] case final Map properties) {
    result['properties'] = <String, Object?>{
      for (final entry in properties.entries)
        if (!names.contains(entry.key.toString()))
          entry.key.toString(): entry.value,
    };
  }
  if (schema['required'] case final List required) {
    final remaining = required
        .whereType<String>()
        .where((name) => !names.contains(name))
        .toList(growable: false);
    if (remaining.isEmpty) {
      result.remove('required');
    } else {
      result['required'] = remaining;
    }
  }
  return result;
}

List<OpenApiParameter> _queryParameters(
  Map<String, Object?> schema,
  List<OpenApiParameter> pathParameters,
) {
  final properties = _schemaProperties(schema);
  final required =
      (schema['required'] as List?)?.whereType<String>().toSet() ??
      const <String>{};
  final pathNames = pathParameters.map((parameter) => parameter.name).toSet();
  return properties.entries
      .where((property) => !pathNames.contains(property.key))
      .map(
        (property) => OpenApiParameter(
          name: property.key,
          location: 'query',
          required: required.contains(property.key),
          schema: property.value,
        ),
      )
      .toList(growable: false);
}

Map<String, Map<String, Object?>> _schemaProperties(
  Map<String, Object?> schema,
) {
  final value = schema['properties'];
  if (value is! Map) return const <String, Map<String, Object?>>{};
  return value.map(
    (name, property) => MapEntry(
      name.toString(),
      property is Map
          ? Map<String, Object?>.from(property)
          : const <String, Object?>{},
    ),
  );
}

Iterable<String> _identifierParts(String value) =>
    RegExp(r'[A-Za-z0-9]+').allMatches(value).map((match) => match.group(0)!);

String _upperFirst(String value) => value.isEmpty
    ? value
    : '${value.substring(0, 1).toUpperCase()}${value.substring(1)}';

String _normalizePath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed == '/') return '/';
  return '/${trimmed.replaceAll(RegExp(r'^/+|/+$'), '')}';
}

String _pluginId(String endpointId) {
  final separator = endpointId.indexOf('.');
  return separator == -1 ? endpointId : endpointId.substring(0, separator);
}

String _summary(String endpointId) =>
    _identifierParts(endpointId).map(_upperFirst).join(' ');
