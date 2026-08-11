/// Annotations for attaching OpenAPI metadata to route handlers.
///
/// These annotations are consumed by:
/// - the analyzer plugin for IDE diagnostics and guidance
/// - the OpenAPI build pipeline as metadata enrichment for route schemas
///
/// The final OpenAPI operation metadata is merged from route `schema:`,
/// handler annotations, and handler Dartdoc comments. When multiple sources
/// define the same scalar field, route `schema:` takes precedence.
library;

/// Marks a handler with an OpenAPI summary (short description).
///
/// ```dart
/// @Summary('List all users')
/// FutureOr<dynamic> listUsers(EngineContext ctx) { ... }
/// ```
class Summary {
  const Summary(this.value);
  final String value;
}

/// Marks a handler with an OpenAPI description (detailed explanation).
///
/// ```dart
/// @Description('Returns a paginated list of all registered users.')
/// FutureOr<dynamic> listUsers(EngineContext ctx) { ... }
/// ```
class Description {
  const Description(this.value);
  final String value;
}

/// Assigns one or more OpenAPI tags to a handler.
///
/// ```dart
/// @Tags(['users', 'admin'])
/// FutureOr<dynamic> listUsers(EngineContext ctx) { ... }
/// ```
class Tags {
  const Tags(this.values);
  final List<String> values;
}

/// Sets the OpenAPI operationId for a handler.
///
/// ```dart
/// @OperationId('listUsers')
/// FutureOr<dynamic> listUsers(EngineContext ctx) { ... }
/// ```
class OperationId {
  const OperationId(this.value);
  final String value;
}

/// Marks a handler as deprecated in the OpenAPI spec.
///
/// ```dart
/// @ApiDeprecated('Use /v2/users instead')
/// FutureOr<dynamic> listUsers(EngineContext ctx) { ... }
/// ```
class ApiDeprecated {
  const ApiDeprecated([this.message]);
  final String? message;
}

/// Hides a handler from the generated OpenAPI spec.
///
/// ```dart
/// @ApiHidden()
/// FutureOr<dynamic> healthCheck(EngineContext ctx) { ... }
/// ```
class ApiHidden {
  const ApiHidden();
}

/// Describes a possible response for a handler.
///
/// ```dart
/// @ApiResponse(200, description: 'User created')
/// @ApiResponse(422, description: 'Validation failed')
/// FutureOr<dynamic> createUser(EngineContext ctx) { ... }
/// ```
class ApiResponse {
  const ApiResponse(
    this.statusCode, {
    this.description = '',
    this.contentType,
    this.schema,
    this.headers,
  });

  final int statusCode;
  final String description;

  /// MIME type for the response body (e.g. 'application/json').
  /// Defaults to 'application/json' when [schema] is provided.
  final String? contentType;

  /// JSON Schema for the response body, as a const map.
  final Map<String, Object?>? schema;

  /// Headers included in the response.
  final Map<String, Object?>? headers;
}

/// Describes a path, query, header, or cookie parameter for a handler.
///
/// ```dart
/// @ApiParam('id', location: ParamLocation.path, description: 'User ID')
/// @ApiParam('q', location: ParamLocation.query, description: 'Search term')
/// FutureOr<dynamic> getUser(EngineContext ctx) { ... }
/// ```
class ApiParam {
  const ApiParam(
    this.name, {
    this.location = ParamLocation.query,
    this.description = '',
    this.required,
    this.schema,
    this.example,
  });

  final String name;
  final ParamLocation location;
  final String description;

  /// Whether the parameter is required. Defaults to `true` for path params,
  /// `false` otherwise.
  final bool? required;

  /// JSON Schema for the parameter value.
  final Map<String, Object?>? schema;

  /// Example value for documentation.
  final Object? example;
}

/// Describes the request body for a handler.
///
/// ```dart
/// @ApiBody(
///   description: 'User creation payload',
///   contentType: 'application/json',
///   required: true,
/// )
/// FutureOr<dynamic> createUser(EngineContext ctx) { ... }
/// ```
class ApiBody {
  const ApiBody({
    this.description = '',
    this.contentType = 'application/json',
    this.required = false,
    this.schema,
  });

  final String description;
  final String contentType;
  final bool required;

  /// JSON Schema for the request body.
  final Map<String, Object?>? schema;
}

/// Location of an API parameter in the HTTP request.
enum ParamLocation { query, path, header, cookie }
