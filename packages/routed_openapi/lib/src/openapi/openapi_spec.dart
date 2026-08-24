/// OpenAPI 3.1 specification data model.
///
/// Lightweight, serializable classes that represent an OpenAPI document.
/// Used by the build_runner generator to produce `openapi.json` and
/// the serving controller `.g.dart` file.
library;

import 'dart:convert';

/// Root of an OpenAPI 3.1 specification document.
class OpenApiSpec {
  /// Creates an OpenAPI document with the supplied root metadata.
  OpenApiSpec({
    required this.info,
    this.openapi = '3.1.0',
    this.servers = const [],
    this.paths = const {},
    this.tags = const [],
    this.components,
  });

  /// Deserializes an OpenAPI document from [json].
  factory OpenApiSpec.fromJson(Map<String, Object?> json) {
    return OpenApiSpec(
      openapi: (json['openapi'] as String?) ?? '3.1.0',
      info: json['info'] is Map<String, Object?>
          ? OpenApiInfo.fromJson(json['info']! as Map<String, Object?>)
          : const OpenApiInfo(title: 'Unknown', version: '0.0.0'),
      servers: json['servers'] is List
          ? (json['servers']! as List)
                .whereType<Map<String, Object?>>()
                .map(OpenApiServer.fromJson)
                .toList()
          : const [],
      paths: json['paths'] is Map<String, Object?>
          ? (json['paths']! as Map<String, Object?>).map(
              (k, v) => MapEntry(
                k,
                OpenApiPathItem.fromJson(v! as Map<String, Object?>),
              ),
            )
          : const {},
      tags: json['tags'] is List
          ? (json['tags']! as List)
                .whereType<Map<String, Object?>>()
                .map(OpenApiTag.fromJson)
                .toList()
          : const [],
      components: json['components'] is Map<String, Object?>
          ? OpenApiComponents.fromJson(
              json['components']! as Map<String, Object?>,
            )
          : null,
    );
  }

  /// The OpenAPI specification version.
  final String openapi;

  /// The document's API metadata.
  final OpenApiInfo info;

  /// Servers where the API is available.
  final List<OpenApiServer> servers;

  /// Operations grouped by their URL path.
  final Map<String, OpenApiPathItem> paths;

  /// Tags used to group operations.
  final List<OpenApiTag> tags;

  /// Reusable schemas and security definitions.
  final OpenApiComponents? components;

  /// Serializes the document to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return {
      'openapi': openapi,
      'info': info.toJson(),
      if (servers.isNotEmpty)
        'servers': servers.map((s) => s.toJson()).toList(),
      if (paths.isNotEmpty)
        'paths': paths.map((k, v) => MapEntry(k, v.toJson())),
      if (tags.isNotEmpty) 'tags': tags.map((t) => t.toJson()).toList(),
      if (components != null && !components!.isEmpty)
        'components': components!.toJson(),
    };
  }

  /// Serializes the document to JSON text.
  String toJsonString({bool pretty = false}) {
    final encoder = pretty
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
    return encoder.convert(toJson());
  }
}

/// Metadata about the API.
class OpenApiInfo {
  /// Creates API metadata with a required [title] and [version].
  const OpenApiInfo({
    required this.title,
    required this.version,
    this.description,
    this.termsOfService,
    this.contact,
    this.license,
  });

  /// Deserializes API metadata from [json].
  factory OpenApiInfo.fromJson(Map<String, Object?> json) {
    return OpenApiInfo(
      title: (json['title'] as String?) ?? 'Unknown',
      version: (json['version'] as String?) ?? '0.0.0',
      description: json['description'] as String?,
      termsOfService: json['termsOfService'] as String?,
      contact: json['contact'] as Map<String, Object?>?,
      license: json['license'] as Map<String, Object?>?,
    );
  }

  /// The name of the API.
  final String title;

  /// The API version presented to consumers.
  final String version;

  /// A longer description of the API.
  final String? description;

  /// A URL describing the API's terms of service.
  final String? termsOfService;

  /// Contact information for the API maintainers.
  final Map<String, Object?>? contact;

  /// License information for the API.
  final Map<String, Object?>? license;

  /// Serializes the metadata to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return {
      'title': title,
      'version': version,
      if (description != null) 'description': description,
      if (termsOfService != null) 'termsOfService': termsOfService,
      if (contact != null) 'contact': contact,
      if (license != null) 'license': license,
    };
  }
}

/// A server URL template.
class OpenApiServer {
  /// Creates a server entry for [url].
  const OpenApiServer({required this.url, this.description});

  /// Deserializes a server entry from [json].
  factory OpenApiServer.fromJson(Map<String, Object?> json) {
    return OpenApiServer(
      url: (json['url'] as String?) ?? '/',
      description: json['description'] as String?,
    );
  }

  /// The server URL or URL template.
  final String url;

  /// An optional explanation of this server.
  final String? description;

  /// Serializes the server entry to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return {'url': url, if (description != null) 'description': description};
  }
}

/// An OpenAPI tag for grouping operations.
class OpenApiTag {
  /// Creates a tag named [name].
  const OpenApiTag({required this.name, this.description});

  /// Deserializes a tag from [json].
  factory OpenApiTag.fromJson(Map<String, Object?> json) {
    return OpenApiTag(
      name: (json['name'] as String?) ?? '',
      description: json['description'] as String?,
    );
  }

  /// The tag name.
  final String name;

  /// An optional explanation of the tag.
  final String? description;

  /// Serializes the tag to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return {'name': name, if (description != null) 'description': description};
  }
}

/// Describes the operations available on a single path.
class OpenApiPathItem {
  /// Creates a path item with its optional operations.
  const OpenApiPathItem({
    this.summary,
    this.description,
    this.get,
    this.put,
    this.post,
    this.delete,
    this.options,
    this.head,
    this.patch,
    this.parameters,
  });

  /// Deserializes a path item from [json].
  factory OpenApiPathItem.fromJson(Map<String, Object?> json) {
    return OpenApiPathItem(
      summary: json['summary'] as String?,
      description: json['description'] as String?,
      get: json['get'] is Map<String, Object?>
          ? OpenApiOperation.fromJson(json['get']! as Map<String, Object?>)
          : null,
      put: json['put'] is Map<String, Object?>
          ? OpenApiOperation.fromJson(json['put']! as Map<String, Object?>)
          : null,
      post: json['post'] is Map<String, Object?>
          ? OpenApiOperation.fromJson(json['post']! as Map<String, Object?>)
          : null,
      delete: json['delete'] is Map<String, Object?>
          ? OpenApiOperation.fromJson(json['delete']! as Map<String, Object?>)
          : null,
      options: json['options'] is Map<String, Object?>
          ? OpenApiOperation.fromJson(json['options']! as Map<String, Object?>)
          : null,
      head: json['head'] is Map<String, Object?>
          ? OpenApiOperation.fromJson(json['head']! as Map<String, Object?>)
          : null,
      patch: json['patch'] is Map<String, Object?>
          ? OpenApiOperation.fromJson(json['patch']! as Map<String, Object?>)
          : null,
      parameters: json['parameters'] is List
          ? (json['parameters']! as List)
                .whereType<Map<String, Object?>>()
                .map(OpenApiParameter.fromJson)
                .toList()
          : null,
    );
  }

  /// A short summary for the path.
  final String? summary;

  /// A detailed description for the path.
  final String? description;

  /// The GET operation, when one is registered.
  final OpenApiOperation? get;

  /// The PUT operation, when one is registered.
  final OpenApiOperation? put;

  /// The POST operation, when one is registered.
  final OpenApiOperation? post;

  /// The DELETE operation, when one is registered.
  final OpenApiOperation? delete;

  /// The OPTIONS operation, when one is registered.
  final OpenApiOperation? options;

  /// The HEAD operation, when one is registered.
  final OpenApiOperation? head;

  /// The PATCH operation, when one is registered.
  final OpenApiOperation? patch;

  /// Parameters shared by operations on this path.
  final List<OpenApiParameter>? parameters;

  /// Returns the operation for the given HTTP [method], or null.
  OpenApiOperation? operationFor(String method) {
    switch (method.toUpperCase()) {
      case 'GET':
        return get;
      case 'PUT':
        return put;
      case 'POST':
        return post;
      case 'DELETE':
        return delete;
      case 'OPTIONS':
        return options;
      case 'HEAD':
        return head;
      case 'PATCH':
        return patch;
      default:
        return null;
    }
  }

  /// Returns a copy with the given operation set for [method].
  OpenApiPathItem withOperation(String method, OpenApiOperation operation) {
    return OpenApiPathItem(
      summary: summary,
      description: description,
      get: method == 'GET' ? operation : get,
      put: method == 'PUT' ? operation : put,
      post: method == 'POST' ? operation : post,
      delete: method == 'DELETE' ? operation : delete,
      options: method == 'OPTIONS' ? operation : options,
      head: method == 'HEAD' ? operation : head,
      patch: method == 'PATCH' ? operation : patch,
      parameters: parameters,
    );
  }

  /// Serializes the path item to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return {
      if (summary != null) 'summary': summary,
      if (description != null) 'description': description,
      if (get != null) 'get': get!.toJson(),
      if (put != null) 'put': put!.toJson(),
      if (post != null) 'post': post!.toJson(),
      if (delete != null) 'delete': delete!.toJson(),
      if (options != null) 'options': options!.toJson(),
      if (head != null) 'head': head!.toJson(),
      if (patch != null) 'patch': patch!.toJson(),
      if (parameters != null && parameters!.isNotEmpty)
        'parameters': parameters!.map((p) => p.toJson()).toList(),
    };
  }
}

/// A single API operation (e.g. GET /users).
class OpenApiOperation {
  /// Creates an operation with its optional request and response metadata.
  const OpenApiOperation({
    this.summary,
    this.description,
    this.operationId,
    this.tags = const [],
    this.parameters = const [],
    this.requestBody,
    this.responses = const {},
    this.security,
    this.deprecated = false,
    this.extensions = const {},
  });

  /// Deserializes an operation from [json].
  factory OpenApiOperation.fromJson(Map<String, Object?> json) {
    return OpenApiOperation(
      summary: json['summary'] as String?,
      description: json['description'] as String?,
      operationId: json['operationId'] as String?,
      tags: json['tags'] is List
          ? (json['tags']! as List).cast<String>()
          : const [],
      parameters: json['parameters'] is List
          ? (json['parameters']! as List)
                .whereType<Map<String, Object?>>()
                .map(OpenApiParameter.fromJson)
                .toList()
          : const [],
      requestBody: json['requestBody'] is Map<String, Object?>
          ? OpenApiRequestBody.fromJson(
              json['requestBody']! as Map<String, Object?>,
            )
          : null,
      responses: json['responses'] is Map<String, Object?>
          ? (json['responses']! as Map<String, Object?>).map(
              (k, v) => MapEntry(
                k,
                OpenApiResponse.fromJson(v! as Map<String, Object?>),
              ),
            )
          : const {},
      security: json['security'] is List
          ? (json['security']! as List)
                .whereType<Map<String, Object?>>()
                .map(
                  (requirement) => requirement.map(
                    (name, scopes) => MapEntry(
                      name,
                      scopes is List ? scopes.cast<String>() : const <String>[],
                    ),
                  ),
                )
                .toList()
          : null,
      deprecated: json['deprecated'] == true,
      extensions: Map<String, Object?>.fromEntries(
        json.entries.where((entry) => entry.key.startsWith('x-')),
      ),
    );
  }

  /// A short summary of the operation.
  final String? summary;

  /// A detailed description of the operation.
  final String? description;

  /// The stable identifier used by generated clients.
  final String? operationId;

  /// Tags grouping this operation.
  final List<String> tags;

  /// Parameters accepted by this operation.
  final List<OpenApiParameter> parameters;

  /// The optional request body.
  final OpenApiRequestBody? requestBody;

  /// Responses keyed by HTTP status code.
  final Map<String, OpenApiResponse> responses;

  /// Per-operation security requirements.
  ///
  /// Each map is an alternative (logical OR). An empty list explicitly marks
  /// an operation as public.
  final List<Map<String, List<String>>>? security;

  /// Whether the operation is deprecated.
  final bool deprecated;

  /// Vendor extensions emitted alongside this operation.
  ///
  /// Extension names should use the OpenAPI `x-` prefix. The auth generator
  /// uses this field for policies that OpenAPI has no first-class vocabulary
  /// for, such as browser Origin validation and namespaced rate limits.
  final Map<String, Object?> extensions;

  /// Serializes the operation to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return {
      if (summary != null) 'summary': summary,
      if (description != null) 'description': description,
      if (operationId != null) 'operationId': operationId,
      if (tags.isNotEmpty) 'tags': tags,
      if (parameters.isNotEmpty)
        'parameters': parameters.map((p) => p.toJson()).toList(),
      if (requestBody != null) 'requestBody': requestBody!.toJson(),
      if (responses.isNotEmpty)
        'responses': responses.map((k, v) => MapEntry(k, v.toJson())),
      if (security != null)
        'security': security!
            .map(
              (requirement) => requirement.map(
                (name, scopes) => MapEntry(name, List<String>.from(scopes)),
              ),
            )
            .toList(),
      if (deprecated) 'deprecated': true,
      ...extensions,
    };
  }
}

/// Reusable OpenAPI components.
class OpenApiComponents {
  /// Creates reusable component definitions.
  const OpenApiComponents({
    this.schemas = const {},
    this.securitySchemes = const {},
  });

  /// Deserializes reusable components from [json].
  factory OpenApiComponents.fromJson(Map<String, Object?> json) {
    return OpenApiComponents(
      schemas: json['schemas'] is Map<String, Object?>
          ? (json['schemas']! as Map<String, Object?>).map(
              (name, schema) =>
                  MapEntry(name, Map<String, Object?>.from(schema! as Map)),
            )
          : const {},
      securitySchemes: json['securitySchemes'] is Map<String, Object?>
          ? (json['securitySchemes']! as Map<String, Object?>).map(
              (name, scheme) => MapEntry(
                name,
                OpenApiSecurityScheme.fromJson(scheme! as Map<String, Object?>),
              ),
            )
          : const {},
    );
  }

  /// Reusable JSON Schemas keyed by component name.
  final Map<String, Map<String, Object?>> schemas;

  /// Reusable security schemes keyed by component name.
  final Map<String, OpenApiSecurityScheme> securitySchemes;

  /// Whether this component collection contains no definitions.
  bool get isEmpty => schemas.isEmpty && securitySchemes.isEmpty;

  /// Serializes the components to a JSON-compatible map.
  Map<String, Object?> toJson() => {
    if (schemas.isNotEmpty) 'schemas': schemas,
    if (securitySchemes.isNotEmpty)
      'securitySchemes': securitySchemes.map(
        (name, scheme) => MapEntry(name, scheme.toJson()),
      ),
  };
}

/// An OpenAPI security scheme used by operation security requirements.
class OpenApiSecurityScheme {
  /// Creates a security scheme of the given OpenAPI [type].
  const OpenApiSecurityScheme({
    required this.type,
    this.description,
    this.name,
    this.location,
    this.scheme,
    this.bearerFormat,
  });

  /// Deserializes a security scheme from [json].
  factory OpenApiSecurityScheme.fromJson(Map<String, Object?> json) {
    return OpenApiSecurityScheme(
      type: (json['type'] as String?) ?? '',
      description: json['description'] as String?,
      name: json['name'] as String?,
      location: json['in'] as String?,
      scheme: json['scheme'] as String?,
      bearerFormat: json['bearerFormat'] as String?,
    );
  }

  /// The OpenAPI security scheme type, such as `apiKey` or `http`.
  final String type;

  /// An optional explanation of the security scheme.
  final String? description;

  /// The header, query, or cookie name for key-based schemes.
  final String? name;

  /// The request location for key-based schemes.
  final String? location;

  /// The HTTP authentication scheme for `http` security schemes.
  final String? scheme;

  /// The bearer token format for bearer authentication.
  final String? bearerFormat;

  /// Serializes the security scheme to a JSON-compatible map.
  Map<String, Object?> toJson() => {
    'type': type,
    if (description != null) 'description': description,
    if (name != null) 'name': name,
    if (location != null) 'in': location,
    if (scheme != null) 'scheme': scheme,
    if (bearerFormat != null) 'bearerFormat': bearerFormat,
  };
}

/// A parameter (path, query, header, or cookie).
class OpenApiParameter {
  /// Creates a parameter with its required name and request [location].
  const OpenApiParameter({
    required this.name,
    required this.location,
    this.description,
    this.required,
    this.schema,
    this.example,
  });

  /// Deserializes a parameter from [json].
  factory OpenApiParameter.fromJson(Map<String, Object?> json) {
    return OpenApiParameter(
      name: (json['name'] as String?) ?? '',
      location: (json['in'] as String?) ?? 'query',
      description: json['description'] as String?,
      required: json['required'] as bool?,
      schema: json['schema'] as Map<String, Object?>?,
      example: json['example'],
    );
  }

  /// The parameter name.
  final String name;

  /// One of: 'query', 'path', 'header', 'cookie'.
  final String location;

  /// The human-readable parameter description.
  final String? description;

  /// Whether this parameter is required. Path parameters are always required.
  final bool? required;

  /// The JSON Schema describing the parameter value.
  final Map<String, Object?>? schema;

  /// An example value for the parameter.
  final Object? example;

  /// Whether this parameter is effectively required.
  bool get isRequired => required ?? (location == 'path');

  /// Serializes the parameter to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return {
      'name': name,
      'in': location,
      if (description != null && description!.isNotEmpty)
        'description': description,
      'required': isRequired,
      if (schema != null) 'schema': schema,
      if (example != null) 'example': example,
    };
  }
}

/// Describes a request body.
class OpenApiRequestBody {
  /// Creates a request body with its content definitions.
  const OpenApiRequestBody({
    this.description,
    this.required = false,
    this.content = const {},
  });

  /// Deserializes a request body from [json].
  factory OpenApiRequestBody.fromJson(Map<String, Object?> json) {
    return OpenApiRequestBody(
      description: json['description'] as String?,
      required: json['required'] == true,
      content: json['content'] is Map<String, Object?>
          ? (json['content']! as Map<String, Object?>).map(
              (k, v) => MapEntry(
                k,
                OpenApiMediaType.fromJson(v! as Map<String, Object?>),
              ),
            )
          : const {},
    );
  }

  /// A human-readable description of the body.
  final String? description;

  /// Whether the operation requires this body.
  final bool required;

  /// Media types accepted for this body, keyed by MIME type.
  final Map<String, OpenApiMediaType> content;

  /// Serializes the request body to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return {
      if (description != null && description!.isNotEmpty)
        'description': description,
      if (required) 'required': true,
      if (content.isNotEmpty)
        'content': content.map((k, v) => MapEntry(k, v.toJson())),
    };
  }
}

/// A media type with its schema.
class OpenApiMediaType {
  /// Creates a media type with an optional schema and example.
  const OpenApiMediaType({this.schema, this.example});

  /// Deserializes a media type from [json].
  factory OpenApiMediaType.fromJson(Map<String, Object?> json) {
    return OpenApiMediaType(
      schema: json['schema'] as Map<String, Object?>?,
      example: json['example'],
    );
  }

  /// The JSON Schema for the media type.
  final Map<String, Object?>? schema;

  /// An example value for the media type.
  final Object? example;

  /// Serializes the media type to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return {
      if (schema != null) 'schema': schema,
      if (example != null) 'example': example,
    };
  }
}

/// Describes a response for a status code.
class OpenApiResponse {
  /// Creates a response with the required [description].
  const OpenApiResponse({
    required this.description,
    this.content,
    this.headers,
  });

  /// Deserializes a response from [json].
  factory OpenApiResponse.fromJson(Map<String, Object?> json) {
    return OpenApiResponse(
      description: (json['description'] as String?) ?? '',
      content: json['content'] is Map<String, Object?>
          ? (json['content']! as Map<String, Object?>).map(
              (k, v) => MapEntry(
                k,
                OpenApiMediaType.fromJson(v! as Map<String, Object?>),
              ),
            )
          : null,
      headers: json['headers'] as Map<String, Object?>?,
    );
  }

  /// The human-readable response description.
  final String description;

  /// Response content keyed by MIME type.
  final Map<String, OpenApiMediaType>? content;

  /// Header definitions included in the response.
  final Map<String, Object?>? headers;

  /// Serializes the response to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return {
      'description': description,
      if (content != null && content!.isNotEmpty)
        'content': content!.map((k, v) => MapEntry(k, v.toJson())),
      if (headers != null && headers!.isNotEmpty) 'headers': headers,
    };
  }
}
