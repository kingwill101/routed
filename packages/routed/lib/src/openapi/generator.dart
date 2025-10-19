import 'dart:collection';

import '../engine/route_manifest.dart';

/// Basic info block for the generated OpenAPI document.
class OpenApiDocumentInfo {
  const OpenApiDocumentInfo({
    required this.title,
    required this.version,
    this.description,
  });

  final String title;
  final String version;
  final String? description;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'title': title,
      'version': version,
      if (description != null && description!.isNotEmpty)
        'description': description,
    };
  }
}

/// Describes a server entry for the document.
class OpenApiServer {
  const OpenApiServer({required this.url, this.description});

  final String url;
  final String? description;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'url': url,
      if (description != null && description!.isNotEmpty)
        'description': description,
    };
  }
}

/// Generates an OpenAPI 3.1 document from a [RouteManifest].
Map<String, Object?> generateOpenApiDocument(
  RouteManifest manifest, {
  required OpenApiDocumentInfo info,
  List<OpenApiServer> servers = const [],
  Map<String, Object?> components = const {},
}) {
  final operationIds = <String, int>{};
  final paths = SplayTreeMap<String, Object?>();

  for (final route in manifest.routes) {
    if (route.method == '*' || route.method.isEmpty) {
      // Skip fallback routes from OpenAPI output.
      continue;
    }
    final methodKey = route.method.toLowerCase();
    final pathMap =
        (paths[route.path] as Map<String, Object?>?) ??
        SplayTreeMap<String, Object?>();

    final operation = _buildOperation(route, operationIds);
    pathMap[methodKey] = operation;
    paths[route.path] = pathMap;
  }

  return <String, Object?>{
    'openapi': '3.1.0',
    'info': info.toJson(),
    if (servers.isNotEmpty)
      'servers': servers.map((server) => server.toJson()).toList(),
    'paths': _serializePaths(paths),
    if (components.isNotEmpty)
      'components': _cloneMap(components.cast<Object?, Object?>()),
  };
}

Map<String, Object?> _buildOperation(
  RouteManifestEntry route,
  Map<String, int> operationIds,
) {
  final metadata = route.constraints['openapi'];
  final operation = metadata is Map
      ? _cloneMap(metadata.cast<Object?, Object?>())
      : <String, Object?>{};

  // Attach route name as vendor extension for traceability.
  if (route.name != null && route.name!.isNotEmpty) {
    operation.putIfAbsent('x-route-name', () => route.name);
  }

  // Ensure summary defaults.
  operation.putIfAbsent('summary', () => _defaultSummary(route));

  // Ensure tags default.
  if (operation['tags'] is! List) {
    operation['tags'] = _defaultTags(route);
  } else {
    final tags = (operation['tags'] as List)
        .whereType<String>()
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList();
    operation['tags'] = tags.isEmpty ? _defaultTags(route) : tags;
  }

  // Parameters: merge path parameters with declared ones.
  final declaredParameters = operation['parameters'] is List
      ? (operation['parameters'] as List)
            .whereType<Map<Object?, Object?>>()
            .map(
              (param) =>
                  param.map((key, value) => MapEntry(key.toString(), value)),
            )
            .toList()
      : <Map<String, Object?>>[];
  final mergedParameters = _mergePathParameters(route, declaredParameters);
  if (mergedParameters.isNotEmpty) {
    operation['parameters'] = mergedParameters;
  }

  // Responses must exist.
  final responses = operation['responses'] is Map
      ? _cloneMap(
          (operation['responses'] as Map<Object?, Object?>).map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        )
      : <String, Object?>{};
  if (responses.isEmpty) {
    responses['200'] = {'description': 'Successful response.'};
  }
  operation['responses'] = responses;

  // OperationId fallback.
  final existingOperationId = operation['operationId'];
  if (existingOperationId is! String || existingOperationId.isEmpty) {
    operation['operationId'] = _generateOperationId(route, operationIds);
  }

  return operation;
}

List<Map<String, Object?>> _mergePathParameters(
  RouteManifestEntry route,
  List<Map<String, Object?>> existing,
) {
  final merged = existing
      .map((param) => _cloneMap(param.cast<Object?, Object?>()))
      .toList(growable: true);
  final existingPathParams = merged
      .where((param) => param['in'] == 'path')
      .map((param) => param['name'])
      .whereType<String>()
      .toSet();

  for (final param in _extractPathParameters(route.path)) {
    if (existingPathParams.contains(param.name)) {
      continue;
    }
    merged.add(param.toJson());
  }

  return merged;
}

List<String> _defaultTags(RouteManifestEntry route) {
  final segments = route.path
      .split('/')
      .where((segment) => segment.isNotEmpty && !segment.startsWith('{'))
      .toList();
  if (segments.isEmpty) {
    return const ['default'];
  }
  return [segments.first];
}

String _defaultSummary(RouteManifestEntry route) {
  if (route.name != null && route.name!.isNotEmpty) {
    return route.name!;
  }
  return '${route.method.toUpperCase()} ${route.path}';
}

String _generateOperationId(
  RouteManifestEntry route,
  Map<String, int> operationIds,
) {
  final sanitizedPath = route.path
      .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  final base =
      '${route.method.toLowerCase()}'
      '_${sanitizedPath.isEmpty ? 'root' : sanitizedPath.toLowerCase()}';
  final index = operationIds.update(
    base,
    (value) => value + 1,
    ifAbsent: () => 0,
  );
  if (index == 0) {
    return base;
  }
  return '${base}_${index + 1}';
}

Iterable<_PathParameter> _extractPathParameters(String path) sync* {
  final regex = RegExp(r'\{([^{}]+)\}');
  for (final match in regex.allMatches(path)) {
    final raw = match.group(1)!;
    var namePart = raw;
    var typePart = '';
    final colonIndex = raw.indexOf(':');
    if (colonIndex != -1) {
      namePart = raw.substring(0, colonIndex);
      typePart = raw.substring(colonIndex + 1);
    }

    var required = true;
    if (namePart.endsWith('?')) {
      namePart = namePart.substring(0, namePart.length - 1);
      required = false;
    }
    if (namePart.endsWith('*')) {
      namePart = namePart.substring(0, namePart.length - 1);
      required = false;
    }

    final schema = _schemaForType(typePart);
    yield _PathParameter(name: namePart, required: required, schema: schema);
  }
}

Map<String, Object?> _schemaForType(String rawType) {
  final type = rawType.trim().toLowerCase();
  switch (type) {
    case 'int':
    case 'integer':
      return {'type': 'integer'};
    case 'double':
    case 'number':
      return {'type': 'number'};
    case 'bool':
    case 'boolean':
      return {'type': 'boolean'};
    case 'uuid':
      return {'type': 'string', 'format': 'uuid'};
    case 'date':
      return {'type': 'string', 'format': 'date'};
    case 'datetime':
    case 'date-time':
      return {'type': 'string', 'format': 'date-time'};
    default:
      return {'type': 'string'};
  }
}

Map<String, Object?> _serializePaths(SplayTreeMap<String, Object?> paths) {
  return Map<String, Object?>.unmodifiable(
    paths.map((key, value) {
      if (value is Map<String, Object?>) {
        return MapEntry(
          key,
          Map<String, Object?>.unmodifiable(
            value.map(
              (innerKey, innerValue) => MapEntry(
                innerKey,
                innerValue is Map<String, Object?>
                    ? Map<String, Object?>.unmodifiable(innerValue)
                    : innerValue,
              ),
            ),
          ),
        );
      }
      return MapEntry(key, value);
    }),
  );
}

Map<String, Object?> _cloneMap(Map<Object?, Object?> source) {
  final cloned = source.map(
    (key, value) => MapEntry(key?.toString() ?? '', _cloneValue(value)),
  );
  cloned.removeWhere((key, _) => key.isEmpty);
  return cloned;
}

Object? _cloneValue(Object? value) {
  if (value is Map<Object?, Object?>) {
    return _cloneMap(value);
  }
  if (value is Map) {
    return _cloneMap(value.cast<Object?, Object?>());
  }
  if (value is List) {
    return value.map(_cloneValue).toList();
  }
  return value;
}

class _PathParameter {
  _PathParameter({
    required this.name,
    required this.required,
    required this.schema,
  });

  final String name;
  final bool required;
  final Map<String, Object?> schema;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'in': 'path',
      'required': required,
      'schema': schema,
    };
  }
}
