/// Builder utilities for attaching OpenAPI operation metadata to Routed routes.
class OpenApiOperationBuilder {
  /// Optional explicit operation identifier.
  String? operationId;

  /// Short summary for the endpoint.
  String? summary;

  /// Longer description for the endpoint.
  String? description;

  final List<String> _tags = [];
  final List<Map<String, Object?>> _parameters = [];
  Map<String, Object?>? _requestBody;
  final Map<String, Object?> _responses = {};

  /// Adds a single tag to the operation.
  void tag(String value) {
    if (value.isEmpty) return;
    _tags.add(value);
  }

  /// Adds multiple tags in one call.
  void tags(Iterable<String> values) {
    for (final value in values) {
      tag(value);
    }
  }

  /// Adds a parameter definition.
  ///
  /// [location] should be one of `path`, `query`, `header`, or `cookie`.
  void parameter({
    required String name,
    String location = 'query',
    bool required = false,
    Map<String, Object?>? schema,
    String? description,
  }) {
    if (name.isEmpty) return;
    final parameter = <String, Object?>{
      'name': name,
      'in': location,
      'required': required,
    };
    if (description != null && description.isNotEmpty) {
      parameter['description'] = description;
    }
    if (schema != null && schema.isNotEmpty) {
      parameter['schema'] = Map<String, Object?>.from(schema);
    }
    _parameters.add(parameter);
  }

  /// Defines the request body for the operation.
  void requestBody({
    Map<String, Object?>? content,
    String? description,
    bool required = true,
  }) {
    if (content == null || content.isEmpty) return;
    _requestBody = <String, Object?>{
      'content': _cloneMap(content),
      'required': required,
      if (description != null && description.isNotEmpty)
        'description': description,
    };
  }

  /// Convenience to define a JSON request body schema.
  void jsonRequestBody({
    required Map<String, Object?> schema,
    String? description,
    bool required = true,
  }) {
    requestBody(
      content: {
        'application/json': {'schema': Map<String, Object?>.from(schema)},
      },
      description: description,
      required: required,
    );
  }

  /// Adds a response entry for the operation.
  void response({
    required String status,
    String description = 'Success',
    Map<String, Object?>? headers,
    Map<String, Object?>? content,
  }) {
    if (status.isEmpty) return;
    final map = <String, Object?>{'description': description};
    if (headers != null && headers.isNotEmpty) {
      map['headers'] = _cloneMap(headers);
    }
    if (content != null && content.isNotEmpty) {
      map['content'] = _cloneMap(content);
    }
    _responses[status] = map;
  }

  /// Convenience for JSON responses.
  void jsonResponse({
    required String status,
    String description = 'Success',
    Map<String, Object?>? schema,
  }) {
    response(
      status: status,
      description: description,
      content: {
        'application/json': {
          if (schema != null) 'schema': Map<String, Object?>.from(schema),
        },
      },
    );
  }

  /// Builds the immutable spec to store on the route.
  OpenApiOperationSpec build() {
    final data = <String, Object?>{};
    if (operationId != null && operationId!.isNotEmpty) {
      data['operationId'] = operationId;
    }
    if (summary != null && summary!.isNotEmpty) {
      data['summary'] = summary;
    }
    if (description != null && description!.isNotEmpty) {
      data['description'] = description;
    }
    if (_tags.isNotEmpty) {
      data['tags'] = List<String>.from(_tags);
    }
    if (_parameters.isNotEmpty) {
      data['parameters'] = _parameters
          .map((parameter) => Map<String, Object?>.from(parameter))
          .toList();
    }
    if (_requestBody != null && _requestBody!.isNotEmpty) {
      data['requestBody'] = Map<String, Object?>.from(_requestBody!);
    }
    if (_responses.isNotEmpty) {
      data['responses'] = _cloneMap(_responses);
    }
    return OpenApiOperationSpec._(data);
  }

  Map<String, Object?> _cloneMap(Map<String, Object?> source) {
    return source.map((key, value) => MapEntry(key, _cloneValue(value)));
  }

  Object? _cloneValue(Object? value) {
    if (value is Map<String, Object?>) {
      return _cloneMap(value);
    }
    if (value is List) {
      return value.map(_cloneValue).toList();
    }
    return value;
  }
}

/// Immutable OpenAPI operation metadata stored on a route.
class OpenApiOperationSpec {
  OpenApiOperationSpec._(Map<String, Object?> data)
    : _data = Map<String, Object?>.unmodifiable(data);

  final Map<String, Object?> _data;

  /// Returns a JSON-serializable representation of the operation.
  Map<String, Object?> toJson() => _data;
}
