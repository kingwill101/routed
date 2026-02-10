/// Converts a [RouteManifest] into an [OpenApiSpec].
///
/// This is the core transformation that turns the runtime route tree
/// (with attached [RouteSchema] metadata) into an OpenAPI 3.1 document.
library;

import 'package:routed/src/engine/route_manifest.dart';
import 'package:routed/src/openapi/openapi_spec.dart';
import 'package:routed/src/openapi/pipe_rule_converter.dart';
import 'package:routed/src/openapi/schema.dart';

/// Configuration for the OpenAPI spec generation.
class OpenApiConfig {
  const OpenApiConfig({
    this.title = 'API',
    this.version = '1.0.0',
    this.description,
    this.servers = const [],
    this.includeHidden = false,
  });

  final String title;
  final String version;
  final String? description;
  final List<OpenApiServer> servers;

  /// Whether to include routes marked with `hidden: true`.
  final bool includeHidden;
}

/// Converts a [RouteManifest] into an [OpenApiSpec].
OpenApiSpec manifestToOpenApi(
  RouteManifest manifest, {
  OpenApiConfig config = const OpenApiConfig(),
}) {
  final paths = <String, OpenApiPathItem>{};
  final tagNames = <String>{};

  for (final route in manifest.routes) {
    // Skip fallback routes — they have no meaningful path.
    if (route.isFallback) continue;

    final schema = route.schema;

    // Skip hidden routes unless explicitly included.
    if (schema != null && schema.hidden && !config.includeHidden) continue;

    // Convert routed path params (:id) to OpenAPI path params ({id}).
    final openApiPath = _convertPath(route.path);
    final method = route.method.toUpperCase();

    // Build the operation for this route.
    final operation = _buildOperation(route, schema);

    // Collect tags.
    tagNames.addAll(operation.tags);

    // Merge into the path item (multiple methods can share a path).
    final existing = paths[openApiPath] ?? const OpenApiPathItem();
    paths[openApiPath] = existing.withOperation(method, operation);
  }

  // Build tag objects from collected names.
  final tags = tagNames.map((name) => OpenApiTag(name: name)).toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  return OpenApiSpec(
    info: OpenApiInfo(
      title: config.title,
      version: config.version,
      description: config.description,
    ),
    servers: config.servers,
    paths: paths,
    tags: tags,
  );
}

/// Builds an [OpenApiOperation] from a [RouteManifestEntry] and its optional
/// [RouteSchema].
OpenApiOperation _buildOperation(
  RouteManifestEntry route,
  RouteSchema? schema,
) {
  final tags = schema?.tags ?? <String>[];
  final operationId = schema?.operationId ?? _generateOperationId(route);
  final parameters = <OpenApiParameter>[];
  final responses = <String, OpenApiResponse>{};

  // Extract path parameters from the path pattern.
  final pathParams = _extractPathParams(route.path);
  for (final param in pathParams) {
    // Check if the schema provides richer info for this param.
    final schemaParam = schema?.params
        ?.where((p) => p.name == param)
        .firstOrNull;
    parameters.add(
      OpenApiParameter(
        name: param,
        location: 'path',
        required: true,
        description: schemaParam?.description,
        schema: schemaParam?.jsonSchema ?? const {'type': 'string'},
        example: schemaParam?.example,
      ),
    );
  }

  // Add non-path parameters from schema.
  if (schema?.params != null) {
    for (final p in schema!.params!) {
      // Skip path params already added above.
      if (p.location.name == 'path') continue;
      parameters.add(
        OpenApiParameter(
          name: p.name,
          location: p.location.name,
          required: p.required,
          description: p.description.isEmpty ? null : p.description,
          schema: p.jsonSchema,
          example: p.example,
        ),
      );
    }
  }

  // Build request body.
  OpenApiRequestBody? requestBody;
  if (schema?.body != null) {
    requestBody = _buildRequestBody(schema!.body!);
  } else if (schema?.validationRules != null &&
      schema!.validationRules!.isNotEmpty) {
    // Auto-generate request body from validation rules.
    requestBody = _buildRequestBodyFromRules(schema.validationRules!);
  }

  // Build responses.
  if (schema?.responses != null && schema!.responses!.isNotEmpty) {
    for (final r in schema.responses!) {
      final statusKey = r.statusCode.toString();
      final contentType =
          r.contentType ?? (r.jsonSchema != null ? 'application/json' : null);
      responses[statusKey] = OpenApiResponse(
        description: r.description.isEmpty
            ? _defaultStatusDescription(r.statusCode)
            : r.description,
        content: r.jsonSchema != null && contentType != null
            ? {contentType: OpenApiMediaType(schema: r.jsonSchema)}
            : null,
        headers: r.headers,
      );
    }
  }

  // Ensure at least a default 200 response.
  if (responses.isEmpty) {
    responses['200'] = const OpenApiResponse(
      description: 'Successful response',
    );
  }

  return OpenApiOperation(
    summary: schema?.summary,
    description: schema?.description,
    operationId: operationId,
    tags: tags,
    parameters: parameters,
    requestBody: requestBody,
    responses: responses,
    deprecated: schema?.deprecated ?? false,
  );
}

/// Builds an [OpenApiRequestBody] from a [BodySchema].
OpenApiRequestBody _buildRequestBody(BodySchema body) {
  Map<String, Object?>? jsonSchema = body.jsonSchema;

  // If the body schema contains pipe-rule markers, convert them.
  if (jsonSchema != null && jsonSchema.containsKey('_validationRules')) {
    final rules = (jsonSchema['_validationRules'] as Map<String, Object?>)
        .cast<String, String>();
    jsonSchema = PipeRuleSchemaConverter.convertRules(rules);
  }

  return OpenApiRequestBody(
    description: body.description.isEmpty ? null : body.description,
    required: body.required,
    content: {body.contentType: OpenApiMediaType(schema: jsonSchema)},
  );
}

/// Builds an [OpenApiRequestBody] from pipe-rule validation rules.
OpenApiRequestBody _buildRequestBodyFromRules(Map<String, String> rules) {
  final jsonSchema = PipeRuleSchemaConverter.convertRules(rules);
  return OpenApiRequestBody(
    required: true,
    content: {'application/json': OpenApiMediaType(schema: jsonSchema)},
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Converts routed-style path parameters (`:id`, `:name`) to OpenAPI-style
/// (`{id}`, `{name}`).
String _convertPath(String path) {
  return path.replaceAllMapped(
    RegExp(r':(\w+)'),
    (match) => '{${match.group(1)}}',
  );
}

/// Extracts path parameter names from a routed-style path.
///
/// `/users/:id/posts/:postId` → `['id', 'postId']`
List<String> _extractPathParams(String path) {
  final matches = RegExp(r':(\w+)').allMatches(path);
  return matches.map((m) => m.group(1)!).toList();
}

/// Generates an operationId from the route's name or method+path.
String _generateOperationId(RouteManifestEntry route) {
  if (route.name != null && route.name!.isNotEmpty) {
    return _camelCase(route.name!);
  }
  // Generate from method + path: GET /users/:id → getUsersId
  final method = route.method.toLowerCase();
  final segments = route.path
      .split('/')
      .where((s) => s.isNotEmpty)
      .map((s) => s.startsWith(':') ? s.substring(1) : s)
      .toList();
  if (segments.isEmpty) return '${method}Root';
  return method + segments.map(_capitalize).join();
}

/// Converts a dotted name like 'users.store' to camelCase 'usersStore'.
String _camelCase(String dotted) {
  final parts = dotted.split('.');
  if (parts.isEmpty) return dotted;
  return parts.first + parts.skip(1).map(_capitalize).join();
}

String _capitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}

/// Returns a standard description for common HTTP status codes.
String _defaultStatusDescription(int statusCode) {
  const descriptions = {
    200: 'OK',
    201: 'Created',
    204: 'No Content',
    301: 'Moved Permanently',
    302: 'Found',
    304: 'Not Modified',
    400: 'Bad Request',
    401: 'Unauthorized',
    403: 'Forbidden',
    404: 'Not Found',
    405: 'Method Not Allowed',
    409: 'Conflict',
    422: 'Unprocessable Entity',
    429: 'Too Many Requests',
    500: 'Internal Server Error',
    502: 'Bad Gateway',
    503: 'Service Unavailable',
  };
  return descriptions[statusCode] ?? 'Response';
}
