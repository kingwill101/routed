/// OpenAPI 3.1 specification data model.
///
/// Lightweight, serializable classes that represent an OpenAPI document.
/// Used by the build_runner generator to produce `openapi.json` and
/// the serving controller `.g.dart` file.
library;

import 'dart:convert';

/// Root of an OpenAPI 3.1 specification document.
class OpenApiSpec {
  OpenApiSpec({
    this.openapi = '3.1.0',
    required this.info,
    this.servers = const [],
    this.paths = const {},
    this.tags = const [],
  });

  final String openapi;
  final OpenApiInfo info;
  final List<OpenApiServer> servers;
  final Map<String, OpenApiPathItem> paths;
  final List<OpenApiTag> tags;

  Map<String, Object?> toJson() {
    return {
      'openapi': openapi,
      'info': info.toJson(),
      if (servers.isNotEmpty)
        'servers': servers.map((s) => s.toJson()).toList(),
      if (paths.isNotEmpty)
        'paths': paths.map((k, v) => MapEntry(k, v.toJson())),
      if (tags.isNotEmpty) 'tags': tags.map((t) => t.toJson()).toList(),
    };
  }

  String toJsonString({bool pretty = false}) {
    final encoder = pretty
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
    return encoder.convert(toJson());
  }

  factory OpenApiSpec.fromJson(Map<String, Object?> json) {
    return OpenApiSpec(
      openapi: (json['openapi'] as String?) ?? '3.1.0',
      info: json['info'] is Map<String, Object?>
          ? OpenApiInfo.fromJson(json['info'] as Map<String, Object?>)
          : const OpenApiInfo(title: 'Unknown', version: '0.0.0'),
      servers: json['servers'] is List
          ? (json['servers'] as List)
                .whereType<Map<String, Object?>>()
                .map(OpenApiServer.fromJson)
                .toList()
          : const [],
      paths: json['paths'] is Map<String, Object?>
          ? (json['paths'] as Map<String, Object?>).map(
              (k, v) => MapEntry(
                k,
                OpenApiPathItem.fromJson(v as Map<String, Object?>),
              ),
            )
          : const {},
      tags: json['tags'] is List
          ? (json['tags'] as List)
                .whereType<Map<String, Object?>>()
                .map(OpenApiTag.fromJson)
                .toList()
          : const [],
    );
  }
}

/// Metadata about the API.
class OpenApiInfo {
  const OpenApiInfo({
    required this.title,
    required this.version,
    this.description,
    this.termsOfService,
    this.contact,
    this.license,
  });

  final String title;
  final String version;
  final String? description;
  final String? termsOfService;
  final Map<String, Object?>? contact;
  final Map<String, Object?>? license;

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
}

/// A server URL template.
class OpenApiServer {
  const OpenApiServer({required this.url, this.description});

  final String url;
  final String? description;

  Map<String, Object?> toJson() {
    return {'url': url, if (description != null) 'description': description};
  }

  factory OpenApiServer.fromJson(Map<String, Object?> json) {
    return OpenApiServer(
      url: (json['url'] as String?) ?? '/',
      description: json['description'] as String?,
    );
  }
}

/// An OpenAPI tag for grouping operations.
class OpenApiTag {
  const OpenApiTag({required this.name, this.description});

  final String name;
  final String? description;

  Map<String, Object?> toJson() {
    return {'name': name, if (description != null) 'description': description};
  }

  factory OpenApiTag.fromJson(Map<String, Object?> json) {
    return OpenApiTag(
      name: (json['name'] as String?) ?? '',
      description: json['description'] as String?,
    );
  }
}

/// Describes the operations available on a single path.
class OpenApiPathItem {
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

  final String? summary;
  final String? description;
  final OpenApiOperation? get;
  final OpenApiOperation? put;
  final OpenApiOperation? post;
  final OpenApiOperation? delete;
  final OpenApiOperation? options;
  final OpenApiOperation? head;
  final OpenApiOperation? patch;
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

  factory OpenApiPathItem.fromJson(Map<String, Object?> json) {
    return OpenApiPathItem(
      summary: json['summary'] as String?,
      description: json['description'] as String?,
      get: json['get'] is Map<String, Object?>
          ? OpenApiOperation.fromJson(json['get'] as Map<String, Object?>)
          : null,
      put: json['put'] is Map<String, Object?>
          ? OpenApiOperation.fromJson(json['put'] as Map<String, Object?>)
          : null,
      post: json['post'] is Map<String, Object?>
          ? OpenApiOperation.fromJson(json['post'] as Map<String, Object?>)
          : null,
      delete: json['delete'] is Map<String, Object?>
          ? OpenApiOperation.fromJson(json['delete'] as Map<String, Object?>)
          : null,
      options: json['options'] is Map<String, Object?>
          ? OpenApiOperation.fromJson(json['options'] as Map<String, Object?>)
          : null,
      head: json['head'] is Map<String, Object?>
          ? OpenApiOperation.fromJson(json['head'] as Map<String, Object?>)
          : null,
      patch: json['patch'] is Map<String, Object?>
          ? OpenApiOperation.fromJson(json['patch'] as Map<String, Object?>)
          : null,
      parameters: json['parameters'] is List
          ? (json['parameters'] as List)
                .whereType<Map<String, Object?>>()
                .map(OpenApiParameter.fromJson)
                .toList()
          : null,
    );
  }
}

/// A single API operation (e.g. GET /users).
class OpenApiOperation {
  const OpenApiOperation({
    this.summary,
    this.description,
    this.operationId,
    this.tags = const [],
    this.parameters = const [],
    this.requestBody,
    this.responses = const {},
    this.deprecated = false,
  });

  final String? summary;
  final String? description;
  final String? operationId;
  final List<String> tags;
  final List<OpenApiParameter> parameters;
  final OpenApiRequestBody? requestBody;
  final Map<String, OpenApiResponse> responses;
  final bool deprecated;

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
      if (deprecated) 'deprecated': true,
    };
  }

  factory OpenApiOperation.fromJson(Map<String, Object?> json) {
    return OpenApiOperation(
      summary: json['summary'] as String?,
      description: json['description'] as String?,
      operationId: json['operationId'] as String?,
      tags: json['tags'] is List
          ? (json['tags'] as List).cast<String>()
          : const [],
      parameters: json['parameters'] is List
          ? (json['parameters'] as List)
                .whereType<Map<String, Object?>>()
                .map(OpenApiParameter.fromJson)
                .toList()
          : const [],
      requestBody: json['requestBody'] is Map<String, Object?>
          ? OpenApiRequestBody.fromJson(
              json['requestBody'] as Map<String, Object?>,
            )
          : null,
      responses: json['responses'] is Map<String, Object?>
          ? (json['responses'] as Map<String, Object?>).map(
              (k, v) => MapEntry(
                k,
                OpenApiResponse.fromJson(v as Map<String, Object?>),
              ),
            )
          : const {},
      deprecated: json['deprecated'] == true,
    );
  }
}

/// A parameter (path, query, header, or cookie).
class OpenApiParameter {
  const OpenApiParameter({
    required this.name,
    required this.location,
    this.description,
    this.required,
    this.schema,
    this.example,
  });

  final String name;

  /// One of: 'query', 'path', 'header', 'cookie'.
  final String location;
  final String? description;

  /// Whether this parameter is required. Path parameters are always required.
  final bool? required;
  final Map<String, Object?>? schema;
  final Object? example;

  /// Whether this parameter is effectively required.
  bool get isRequired => required ?? (location == 'path');

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
}

/// Describes a request body.
class OpenApiRequestBody {
  const OpenApiRequestBody({
    this.description,
    this.required = false,
    this.content = const {},
  });

  final String? description;
  final bool required;
  final Map<String, OpenApiMediaType> content;

  Map<String, Object?> toJson() {
    return {
      if (description != null && description!.isNotEmpty)
        'description': description,
      if (required) 'required': true,
      if (content.isNotEmpty)
        'content': content.map((k, v) => MapEntry(k, v.toJson())),
    };
  }

  factory OpenApiRequestBody.fromJson(Map<String, Object?> json) {
    return OpenApiRequestBody(
      description: json['description'] as String?,
      required: json['required'] == true,
      content: json['content'] is Map<String, Object?>
          ? (json['content'] as Map<String, Object?>).map(
              (k, v) => MapEntry(
                k,
                OpenApiMediaType.fromJson(v as Map<String, Object?>),
              ),
            )
          : const {},
    );
  }
}

/// A media type with its schema.
class OpenApiMediaType {
  const OpenApiMediaType({this.schema, this.example});

  final Map<String, Object?>? schema;
  final Object? example;

  Map<String, Object?> toJson() {
    return {
      if (schema != null) 'schema': schema,
      if (example != null) 'example': example,
    };
  }

  factory OpenApiMediaType.fromJson(Map<String, Object?> json) {
    return OpenApiMediaType(
      schema: json['schema'] as Map<String, Object?>?,
      example: json['example'],
    );
  }
}

/// Describes a response for a status code.
class OpenApiResponse {
  const OpenApiResponse({
    required this.description,
    this.content,
    this.headers,
  });

  final String description;
  final Map<String, OpenApiMediaType>? content;
  final Map<String, Object?>? headers;

  Map<String, Object?> toJson() {
    return {
      'description': description,
      if (content != null && content!.isNotEmpty)
        'content': content!.map((k, v) => MapEntry(k, v.toJson())),
      if (headers != null && headers!.isNotEmpty) 'headers': headers,
    };
  }

  factory OpenApiResponse.fromJson(Map<String, Object?> json) {
    return OpenApiResponse(
      description: (json['description'] as String?) ?? '',
      content: json['content'] is Map<String, Object?>
          ? (json['content'] as Map<String, Object?>).map(
              (k, v) => MapEntry(
                k,
                OpenApiMediaType.fromJson(v as Map<String, Object?>),
              ),
            )
          : null,
      headers: json['headers'] as Map<String, Object?>?,
    );
  }
}
