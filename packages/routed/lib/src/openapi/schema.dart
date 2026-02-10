/// Data classes for describing route schemas at the framework level.
///
/// A [RouteSchema] bundles request body, parameter, and response metadata
/// for a single route. It serves as the single source of truth consumed by:
/// - Runtime auto-validation (Phase 1)
/// - Build-runner OpenAPI generation (Phase 2)
/// - Analyzer plugin linting (Phase 3)
library;

import 'package:routed/src/openapi/annotations.dart';

/// Describes the schema for a single route's request/response contract.
///
/// ```dart
/// engine.post('/users', createUser, schema: RouteSchema(
///   summary: 'Create a new user',
///   tags: ['users'],
///   body: BodySchema(
///     description: 'User creation payload',
///     required: true,
///     jsonSchema: {'type': 'object', 'properties': {'name': {'type': 'string'}}},
///   ),
///   responses: [
///     ResponseSchema(201, description: 'User created'),
///     ResponseSchema(422, description: 'Validation failed'),
///   ],
/// ));
/// ```
class RouteSchema {
  const RouteSchema({
    this.summary,
    this.description,
    this.tags,
    this.operationId,
    this.deprecated = false,
    this.hidden = false,
    this.body,
    this.params,
    this.responses,
    this.validationRules,
  });

  /// Short summary of what this route does.
  final String? summary;

  /// Detailed description of the route behavior.
  final String? description;

  /// OpenAPI tags for grouping.
  final List<String>? tags;

  /// Explicit operationId (auto-generated if null).
  final String? operationId;

  /// Whether this route is deprecated.
  final bool deprecated;

  /// Whether to hide this route from generated specs.
  final bool hidden;

  /// Request body schema.
  final BodySchema? body;

  /// Parameter schemas (path, query, header, cookie).
  final List<ParamSchema>? params;

  /// Response schemas by status code.
  final List<ResponseSchema>? responses;

  /// Pipe-rule validation strings keyed by field name.
  ///
  /// These are automatically converted to JSON Schema at runtime and used
  /// for both request validation and OpenAPI schema generation.
  ///
  /// ```dart
  /// RouteSchema(
  ///   validationRules: {
  ///     'name': 'required|string|min:2|max:100',
  ///     'email': 'required|email',
  ///     'age': 'integer|min:0|max:150',
  ///   },
  /// )
  /// ```
  final Map<String, String>? validationRules;

  /// Creates a [RouteSchema] with only validation rules.
  ///
  /// Shorthand for routes that primarily need request validation.
  factory RouteSchema.fromRules(Map<String, String> rules) {
    return RouteSchema(validationRules: rules);
  }

  /// Deserializes from a JSON map (e.g. from a route manifest).
  factory RouteSchema.fromJson(Map<String, Object?> json) {
    return RouteSchema(
      summary: json['summary'] as String?,
      description: json['description'] as String?,
      tags: json['tags'] is List ? (json['tags'] as List).cast<String>() : null,
      operationId: json['operationId'] as String?,
      deprecated: json['deprecated'] == true,
      hidden: json['hidden'] == true,
      body: json['body'] is Map
          ? BodySchema.fromJson(_stringKeyed(json['body'] as Map))
          : null,
      params: json['params'] is List
          ? (json['params'] as List)
                .whereType<Map<Object?, Object?>>()
                .map((p) => ParamSchema.fromJson(_stringKeyed(p)))
                .toList()
          : null,
      responses: json['responses'] is List
          ? (json['responses'] as List)
                .whereType<Map<Object?, Object?>>()
                .map((r) => ResponseSchema.fromJson(_stringKeyed(r)))
                .toList()
          : null,
      validationRules: json['validationRules'] is Map
          ? (json['validationRules'] as Map).cast<String, String>()
          : null,
    );
  }

  /// Serializes to JSON for route manifest output.
  Map<String, Object?> toJson() {
    return {
      if (summary != null) 'summary': summary,
      if (description != null) 'description': description,
      if (tags != null && tags!.isNotEmpty) 'tags': tags,
      if (operationId != null) 'operationId': operationId,
      if (deprecated) 'deprecated': true,
      if (hidden) 'hidden': true,
      if (body != null) 'body': body!.toJson(),
      if (params != null && params!.isNotEmpty)
        'params': params!.map((p) => p.toJson()).toList(),
      if (responses != null && responses!.isNotEmpty)
        'responses': responses!.map((r) => r.toJson()).toList(),
      if (validationRules != null && validationRules!.isNotEmpty)
        'validationRules': validationRules,
    };
  }
}

/// Describes a request body schema.
class BodySchema {
  const BodySchema({
    this.description = '',
    this.contentType = 'application/json',
    this.required = false,
    this.jsonSchema,
  });

  final String description;
  final String contentType;
  final bool required;

  /// JSON Schema (Draft 2020-12 / OpenAPI 3.1 compatible) for the body.
  final Map<String, Object?>? jsonSchema;

  /// Creates a [BodySchema] from pipe-rule validation strings.
  ///
  /// The rules are stored as-is; conversion to JSON Schema happens
  /// at runtime via the validation bridge (Step 1.6).
  factory BodySchema.fromRules(
    Map<String, String> rules, {
    String description = '',
    bool required = false,
  }) {
    return BodySchema(
      description: description,
      required: required,
      jsonSchema: {'_validationRules': rules},
    );
  }

  /// Deserializes from a JSON map.
  factory BodySchema.fromJson(Map<String, Object?> json) {
    return BodySchema(
      description: (json['description'] as String?) ?? '',
      contentType: (json['contentType'] as String?) ?? 'application/json',
      required: json['required'] == true,
      jsonSchema: json['schema'] is Map
          ? _stringKeyed(json['schema'] as Map)
          : null,
    );
  }

  Map<String, Object?> toJson() {
    return {
      if (description.isNotEmpty) 'description': description,
      'contentType': contentType,
      if (required) 'required': true,
      if (jsonSchema != null) 'schema': jsonSchema,
    };
  }
}

/// Describes a path, query, header, or cookie parameter.
class ParamSchema {
  const ParamSchema(
    this.name, {
    this.location = ParamLocation.query,
    this.description = '',
    this.required,
    this.jsonSchema,
    this.example,
  });

  final String name;
  final ParamLocation location;
  final String description;

  /// Whether the parameter is required. Defaults to `true` for path params,
  /// `false` otherwise.
  final bool? required;

  /// JSON Schema for the parameter value.
  final Map<String, Object?>? jsonSchema;

  /// Example value for documentation.
  final Object? example;

  /// Whether this parameter is effectively required.
  bool get isRequired => required ?? (location == ParamLocation.path);

  /// Deserializes from a JSON map.
  factory ParamSchema.fromJson(Map<String, Object?> json) {
    return ParamSchema(
      json['name'] as String? ?? '',
      location: _parseParamLocation(json['in'] as String?),
      description: (json['description'] as String?) ?? '',
      required: json['required'] as bool?,
      jsonSchema: json['schema'] is Map
          ? _stringKeyed(json['schema'] as Map)
          : null,
      example: json['example'],
    );
  }

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'in': location.name,
      if (description.isNotEmpty) 'description': description,
      'required': isRequired,
      if (jsonSchema != null) 'schema': jsonSchema,
      if (example != null) 'example': example,
    };
  }
}

/// Describes a response for a given status code.
class ResponseSchema {
  const ResponseSchema(
    this.statusCode, {
    this.description = '',
    this.contentType,
    this.jsonSchema,
    this.headers,
  });

  final int statusCode;
  final String description;

  /// MIME type (e.g. 'application/json'). Defaults to 'application/json'
  /// when [jsonSchema] is provided.
  final String? contentType;

  /// JSON Schema for the response body.
  final Map<String, Object?>? jsonSchema;

  /// Header schemas for this response.
  final Map<String, Object?>? headers;

  /// Deserializes from a JSON map.
  factory ResponseSchema.fromJson(Map<String, Object?> json) {
    return ResponseSchema(
      (json['status'] as num?)?.toInt() ?? 200,
      description: (json['description'] as String?) ?? '',
      contentType: json['contentType'] as String?,
      jsonSchema: json['schema'] is Map
          ? _stringKeyed(json['schema'] as Map)
          : null,
      headers: json['headers'] is Map
          ? _stringKeyed(json['headers'] as Map)
          : null,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'status': statusCode,
      if (description.isNotEmpty) 'description': description,
      if (contentType != null) 'contentType': contentType,
      if (jsonSchema != null) 'schema': jsonSchema,
      if (headers != null) 'headers': headers,
    };
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Converts a loosely-typed [Map] to `Map<String, Object?>`, dropping entries
/// whose key is null or empty.
Map<String, Object?> _stringKeyed(Map<Object?, Object?>? source) {
  if (source == null || source.isEmpty) return const <String, Object?>{};
  return source.map((key, value) => MapEntry(key?.toString() ?? '', value))
    ..removeWhere((key, _) => key.isEmpty);
}

/// Parses a string into a [ParamLocation] enum value.
///
/// Falls back to [ParamLocation.query] for unrecognised or null values.
ParamLocation _parseParamLocation(String? value) {
  if (value == null) return ParamLocation.query;
  for (final loc in ParamLocation.values) {
    if (loc.name == value) return loc;
  }
  return ParamLocation.query;
}
