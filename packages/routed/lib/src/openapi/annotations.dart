library;

/// OpenAPI annotations for handler functions.
///
/// These annotations can be placed on handler functions to provide
/// OpenAPI metadata for API documentation generation.
///
/// Example:
/// ```dart
/// @Summary('Get all products')
/// @Description('Returns a list of all products.')
/// @Tags(['products', 'catalog'])
/// @ApiResponse(200, description: 'Success')
/// @ApiResponse(404, description: 'Not found')
/// Future<Response> getProducts(EngineContext ctx) async { ... }
/// ```
///
/// Provides a short summary for the OpenAPI operation.
class Summary {
  final String value;
  const Summary(this.value);
}

/// Provides a longer description for the OpenAPI operation.
class Description {
  final String value;
  const Description(this.value);
}

/// Adds tags to the OpenAPI operation for grouping.
class ApiTags {
  final List<String> values;
  const ApiTags(this.values);
}

/// Marks the operation as deprecated in OpenAPI.
class ApiDeprecated {
  final String? reason;
  const ApiDeprecated([this.reason]);
}

/// Specifies the operation ID for the OpenAPI operation.
class OperationId {
  final String value;
  const OperationId(this.value);
}

/// Defines a response for the OpenAPI operation.
class ApiResponse {
  /// HTTP status code (e.g., 200, 404, 500)
  final int status;

  /// Description of the response
  final String description;

  /// Example response body
  final Object? example;

  /// JSON schema for the response body
  final Map<String, Object?>? schema;

  /// Content type (defaults to 'application/json')
  final String contentType;

  const ApiResponse(
    this.status, {
    this.description = 'Success',
    this.example,
    this.schema,
    this.contentType = 'application/json',
  });
}

/// Provides an example for the request body in OpenAPI.
class RequestExample {
  /// Example request body
  final Object value;

  /// Description of the example
  final String? description;

  const RequestExample(this.value, {this.description});
}

/// Defines a request body for the OpenAPI operation.
class RequestBody {
  /// Description of the request body
  final String? description;

  /// Whether the request body is required
  final bool required;

  /// Content type (defaults to 'application/json')
  final String contentType;

  /// JSON schema for the request body
  final Map<String, Object?>? schema;

  /// Example request body
  final Object? example;

  const RequestBody({
    this.description,
    this.required = true,
    this.contentType = 'application/json',
    this.schema,
    this.example,
  });
}

/// Defines a parameter for the OpenAPI operation.
class ApiParameter {
  /// Parameter name
  final String name;

  /// Parameter location: 'query', 'path', 'header', 'cookie'
  final String location;

  /// Description of the parameter
  final String? description;

  /// Whether the parameter is required
  final bool required;

  /// JSON schema for the parameter
  final Map<String, Object?>? schema;

  /// Example value
  final Object? example;

  const ApiParameter({
    required this.name,
    this.location = 'query',
    this.description,
    this.required = false,
    this.schema,
    this.example,
  });
}

/// Hides the operation from OpenAPI documentation.
class ApiHidden {
  const ApiHidden();
}
