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
  /// Creates a summary annotation with [value].
  const Summary(this.value);

  /// The short OpenAPI summary.
  final String value;
}

/// Marks a handler with an OpenAPI description (detailed explanation).
///
/// ```dart
/// @Description('Returns a paginated list of all registered users.')
/// FutureOr<dynamic> listUsers(EngineContext ctx) { ... }
/// ```
class Description {
  /// Creates a description annotation with [value].
  const Description(this.value);

  /// The detailed OpenAPI description.
  final String value;
}

/// Assigns one or more OpenAPI tags to a handler.
///
/// ```dart
/// @Tags(['users', 'admin'])
/// FutureOr<dynamic> listUsers(EngineContext ctx) { ... }
/// ```
class Tags {
  /// Creates a tags annotation with [values].
  const Tags(this.values);

  /// The OpenAPI tags assigned to the handler.
  final List<String> values;
}

/// Sets the OpenAPI operationId for a handler.
///
/// ```dart
/// @OperationId('listUsers')
/// FutureOr<dynamic> listUsers(EngineContext ctx) { ... }
/// ```
class OperationId {
  /// Creates an operation ID annotation with [value].
  const OperationId(this.value);

  /// The stable OpenAPI operation ID.
  final String value;
}

/// Marks a handler as deprecated in the OpenAPI spec.
///
/// ```dart
/// @ApiDeprecated('Use /v2/users instead')
/// FutureOr<dynamic> listUsers(EngineContext ctx) { ... }
/// ```
class ApiDeprecated {
  /// Creates a deprecation annotation with an optional [message].
  const ApiDeprecated([this.message]);

  /// The optional explanation shown for the deprecation.
  final String? message;
}

/// Hides a handler from the generated OpenAPI spec.
///
/// ```dart
/// @ApiHidden()
/// FutureOr<dynamic> healthCheck(EngineContext ctx) { ... }
/// ```
class ApiHidden {
  /// Creates an annotation that hides the handler from generated documents.
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
  /// Creates a response annotation for [statusCode].
  const ApiResponse(
    this.statusCode, {
    this.description = '',
    this.contentType,
    this.schema,
    this.headers,
  });

  /// The HTTP status code represented by this response.
  final int statusCode;

  /// The human-readable response description.
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
  /// Creates a parameter annotation with [name] and its request [location].
  const ApiParam(
    this.name, {
    this.location = ParamLocation.query,
    this.description = '',
    this.required,
    this.schema,
    this.example,
  });

  /// The parameter name.
  final String name;

  /// Where the parameter is supplied in the request.
  final ParamLocation location;

  /// The human-readable parameter description.
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
  /// Creates a request-body annotation with the supplied metadata.
  const ApiBody({
    this.description = '',
    this.contentType = 'application/json',
    this.required = false,
    this.schema,
  });

  /// The human-readable body description.
  final String description;

  /// The media type accepted by the operation.
  final String contentType;

  /// Whether the request must include the body.
  final bool required;

  /// JSON Schema for the request body.
  final Map<String, Object?>? schema;
}

/// Location of an API parameter in the HTTP request.
enum ParamLocation {
  /// A parameter supplied in the URL query string.
  query,

  /// A parameter embedded in the route path.
  path,

  /// A parameter supplied as an HTTP header.
  header,

  /// A parameter supplied in an HTTP cookie.
  cookie,
}
