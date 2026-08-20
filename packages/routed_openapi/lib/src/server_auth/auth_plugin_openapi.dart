import 'package:server_auth/server_auth.dart';

import '../openapi/openapi_spec.dart';

/// Transport advertised for session-authenticated plugin operations.
enum AuthOpenApiSessionSecurity { cookie, bearer, cookieOrBearer }

/// OpenAPI generation settings for a composed auth plugin registry.
final class AuthPluginOpenApiConfig {
  const AuthPluginOpenApiConfig({
    this.basePath = '/auth',
    this.includeServerOnly = false,
    this.sessionSecurity = AuthOpenApiSessionSecurity.cookieOrBearer,
    this.sessionCookieName = 'routed_session',
    this.csrfHeaderName = 'x-csrf-token',
    this.operationIdPrefix = 'auth',
    this.absolutePathPrefixes = const <String>['/.well-known/'],
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

  /// Prefix used for stable, generated-client-safe operation IDs.
  final String operationIdPrefix;

  /// Endpoint path prefixes that remain rooted instead of using [basePath].
  final List<String> absolutePathPrefixes;
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

    for (final endpoint in registry.endpoints) {
      if (endpoint.serverOnly && !config.includeServerOnly) continue;

      final path = _resolvePath(endpoint.path);
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
      schemas[requestSchemaName] = Map<String, Object?>.from(
        contracts.request.schema,
      );
      schemas[responseSchemaName] = Map<String, Object?>.from(
        contracts.response.schema,
      );

      final pathParameters = _pathParameters(path, contracts.request.schema);
      final parameters = <OpenApiParameter>[
        ...pathParameters,
        if (endpoint.method == AuthOperationMethod.get)
          ..._queryParameters(contracts.request.schema, pathParameters),
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
      requiresSession |= sessionRequired;
      final operation = OpenApiOperation(
        summary: _summary(endpoint.id),
        operationId: operationId,
        tags: <String>[pluginId],
        parameters: parameters,
        requestBody: endpoint.method == AuthOperationMethod.post
            ? OpenApiRequestBody(
                required: contracts.request.required,
                content: <String, OpenApiMediaType>{
                  contracts.request.contentType: OpenApiMediaType(
                    schema: <String, Object?>{
                      r'$ref': '#/components/schemas/$requestSchemaName',
                    },
                  ),
                },
              )
            : null,
        responses: <String, OpenApiResponse>{
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
          if (sessionRequired)
            '401': const OpenApiResponse(
              description: 'Authentication required.',
            ),
          if (endpoint.csrfPolicy == AuthOperationCsrfPolicy.required)
            '403': const OpenApiResponse(
              description: 'CSRF validation failed.',
            ),
          if (endpoint.rateLimitOperation != null)
            '429': const OpenApiResponse(description: 'Rate limit exceeded.'),
        },
        security: sessionRequired ? _sessionSecurity() : const [],
      );

      final existing = paths[path] ?? const OpenApiPathItem();
      if (existing.operationFor(method) != null) {
        throw AuthOpenApiContractException('Duplicate auth route "$routeKey".');
      }
      paths[path] = existing.withOperation(method, operation);
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
        securitySchemes: requiresSession ? _securitySchemes() : const {},
      ),
    );
  }

  String _resolvePath(String endpointPath) {
    final endpoint = _normalizePath(endpointPath);
    if (config.absolutePathPrefixes.any(endpoint.startsWith)) return endpoint;
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
    }
  }

  Map<String, OpenApiSecurityScheme> _securitySchemes() {
    final schemes = <String, OpenApiSecurityScheme>{};
    if (config.sessionSecurity != AuthOpenApiSessionSecurity.bearer) {
      schemes[sessionCookieSecurityScheme] = OpenApiSecurityScheme(
        type: 'apiKey',
        name: config.sessionCookieName,
        location: 'cookie',
        description: 'Routed auth session cookie.',
      );
    }
    if (config.sessionSecurity != AuthOpenApiSessionSecurity.cookie) {
      schemes[bearerSecurityScheme] = const OpenApiSecurityScheme(
        type: 'http',
        scheme: 'bearer',
        description: 'Routed auth bearer token.',
      );
    }
    return schemes;
  }
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

({AuthOperationContract request, AuthOperationContract response}) _contracts(
  AuthEndpointDescriptor<Object?> endpoint,
) {
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
  String path,
  Map<String, Object?> schema,
) {
  final properties = _schemaProperties(schema);
  return RegExp(r'\{([^}]+)\}')
      .allMatches(path)
      .map((match) => match.group(1)!)
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
