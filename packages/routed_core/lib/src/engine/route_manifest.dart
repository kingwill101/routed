import 'dart:convert';

import 'package:routed_core/src/engine/engine.dart';

/// A serializable snapshot of the engine's registered routes.
class RouteManifest {
  /// Creates a route manifest.
  RouteManifest({
    DateTime? generatedAt,
    Iterable<RouteManifestEntry> routes = const [],
    Iterable<WebSocketRouteManifestEntry> webSockets = const [],
    Iterable<String> validationRuleNames = const [],
  }) : generatedAt = generatedAt ?? DateTime.now().toUtc(),
       routes = List<RouteManifestEntry>.unmodifiable(routes),
       webSockets = List<WebSocketRouteManifestEntry>.unmodifiable(webSockets),
       validationRuleNames = List<String>.unmodifiable(validationRuleNames);

  /// Reconstructs a manifest from a JSON-compatible map.
  factory RouteManifest.fromJson(Map<String, Object?> json) {
    final generatedAtRaw = json['generatedAt'];
    DateTime? generatedAt;
    if (generatedAtRaw is String) {
      generatedAt = DateTime.tryParse(generatedAtRaw);
    }

    final routesJson = json['routes'];
    final routes = routesJson is List
        ? routesJson
              .whereType<Map<Object?, Object?>>()
              .map((route) => RouteManifestEntry.fromJson(_stringKeyed(route)))
              .toList()
        : const <RouteManifestEntry>[];

    final webSocketsJson = json['webSockets'];
    final webSockets = webSocketsJson is List
        ? webSocketsJson
              .whereType<Map<Object?, Object?>>()
              .map(
                (entry) =>
                    WebSocketRouteManifestEntry.fromJson(_stringKeyed(entry)),
              )
              .toList()
        : const <WebSocketRouteManifestEntry>[];

    final validationNamesJson = json['validationRuleNames'];
    final validationRuleNames = validationNamesJson is List
        ? validationNamesJson
              .whereType<Object>()
              .map((value) => value.toString())
              .toList()
        : const <String>[];

    return RouteManifest(
      generatedAt: generatedAt,
      routes: routes,
      webSockets: webSockets,
      validationRuleNames: validationRuleNames,
    );
  }

  /// Timestamp (UTC) when the manifest was produced.
  final DateTime generatedAt;

  /// HTTP routes exposed by the engine.
  final List<RouteManifestEntry> routes;

  /// Registered WebSocket routes.
  final List<WebSocketRouteManifestEntry> webSockets;

  /// Names of validation rules registered in the engine.
  final List<String> validationRuleNames;

  /// Converts this manifest to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'generatedAt': generatedAt.toIso8601String(),
      'routes': routes.map((route) => route.toJson()).toList(growable: false),
      'webSockets': webSockets
          .map((route) => route.toJson())
          .toList(growable: false),
      if (validationRuleNames.isNotEmpty)
        'validationRuleNames': validationRuleNames.toList(growable: false),
    };
  }

  /// Converts the manifest to a JSON string.
  String toJsonString({bool pretty = false}) {
    final encoder = pretty
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
    return encoder.convert(toJson());
  }
}

/// Describes a single HTTP route registered with the engine.
class RouteManifestEntry {
  /// Creates a manifest entry for an HTTP route.
  RouteManifestEntry({
    required this.method,
    required this.path,
    this.name,
    this.handlerIdentity,
    Iterable<String> middleware = const [],
    Map<String, Object?> constraints = const {},
    Map<String, Object?> metadata = const {},
    this.sourceFile,
    this.sourceLine,
    this.sourceColumn,
    this.isFallback = false,
    this.schema,
  }) : middleware = List<String>.unmodifiable(middleware),
       constraints = Map<String, Object?>.unmodifiable(constraints),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  /// Creates an entry from a compiled [route].
  factory RouteManifestEntry.fromEngineRoute(EngineRoute route) {
    // Keep generic Object for handlerIdentity/schema to support both routed and routed_openapi RouteSchema
    return RouteManifestEntry(
      method: route.method,
      path: route.path,
      name: route.name,
      middleware: route.middlewares.map(_describeMiddleware),
      constraints: _serializeConstraints(route.constraints),
      metadata: _serializeMetadata(route.metadata.asMap),
      sourceFile: route.sourceFile,
      sourceLine: route.sourceLine,
      sourceColumn: route.sourceColumn,
      isFallback: route.isFallback,
      schema: route.schema,
    );
  }

  /// Reconstructs an entry from a JSON-compatible map.
  factory RouteManifestEntry.fromJson(Map<String, Object?> json) {
    final method = json['method']?.toString() ?? 'GET';
    final path = json['path']?.toString() ?? '/';
    final name = json['name']?.toString();
    final middleware = json['middleware'] is List
        ? (json['middleware']! as List)
              .whereType<Object>()
              .map((value) => value.toString())
              .toList()
        : const <String>[];
    final constraints = json['constraints'] is Map
        ? _stringKeyed(json['constraints']! as Map)
        : const <String, Object?>{};
    final isFallback = json['isFallback'] == true;
    return RouteManifestEntry(
      method: method,
      path: path,
      name: name?.isEmpty ?? false ? null : name,
      handlerIdentity: json['handlerIdentity'],
      middleware: middleware,
      constraints: constraints,
      metadata: json['metadata'] is Map
          ? _stringKeyed(json['metadata']! as Map)
          : const <String, Object?>{},
      sourceFile: json['sourceFile']?.toString(),
      sourceLine: (json['sourceLine'] as num?)?.toInt(),
      sourceColumn: (json['sourceColumn'] as num?)?.toInt(),
      isFallback: isFallback,
      schema: json['schema'],
    );
  }

  /// The HTTP method registered for the route.
  final String method;

  /// The route path pattern.
  final String path;

  /// The optional route name used for URL generation.
  final String? name;

  /// A serializable identity for the route handler, when available.
  final Object? handlerIdentity;

  /// Descriptions of middleware attached to the route.
  final List<String> middleware;

  /// Serializable route constraint values.
  final Map<String, Object?> constraints;

  /// Serializable route metadata.
  final Map<String, Object?> metadata;

  /// The source file where the route was registered.
  final String? sourceFile;

  /// The source line where the route was registered.
  final int? sourceLine;

  /// The source column where the route was registered.
  final int? sourceColumn;

  /// Whether this entry represents a fallback route.
  final bool isFallback;

  /// Optional API schema metadata for this route.
  final Object? schema;

  /// Converts this entry to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'method': method,
      'path': path,
      if (name != null) 'name': name,
      if (handlerIdentity != null) 'handlerIdentity': handlerIdentity,
      if (middleware.isNotEmpty) 'middleware': middleware,
      if (constraints.isNotEmpty) 'constraints': constraints,
      if (metadata.isNotEmpty) 'metadata': metadata,
      if (sourceFile != null) 'sourceFile': sourceFile,
      if (sourceLine != null) 'sourceLine': sourceLine,
      if (sourceColumn != null) 'sourceColumn': sourceColumn,
      if (isFallback) 'isFallback': true,
      if (schema != null) 'schema': schema,
    };
  }
}

/// Describes a WebSocket route in the manifest output.
class WebSocketRouteManifestEntry {
  /// Creates a manifest entry for a WebSocket route.
  WebSocketRouteManifestEntry({
    required this.path,
    Iterable<String> middleware = const [],
  }) : middleware = List<String>.unmodifiable(middleware);

  /// Creates an entry from a compiled WebSocket [route].
  factory WebSocketRouteManifestEntry.fromRoute(
    String path,
    WebSocketEngineRoute route,
  ) {
    return WebSocketRouteManifestEntry(
      path: path,
      middleware: route.middlewares.map(_describeMiddleware),
    );
  }

  /// Reconstructs an entry from a JSON-compatible map.
  factory WebSocketRouteManifestEntry.fromJson(Map<String, Object?> json) {
    final path = json['path']?.toString() ?? '/';
    final middleware = json['middleware'] is List
        ? (json['middleware']! as List)
              .whereType<Object>()
              .map((value) => value.toString())
              .toList()
        : const <String>[];
    return WebSocketRouteManifestEntry(path: path, middleware: middleware);
  }

  /// The WebSocket route path pattern.
  final String path;

  /// Descriptions of middleware attached to the route.
  final List<String> middleware;

  /// Converts this entry to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'path': path,
      if (middleware.isNotEmpty) 'middleware': middleware,
    };
  }
}

/// Adds route-manifest inspection to an [Engine].
extension EngineRouteManifestX on Engine {
  /// Generates a [RouteManifest] for the current engine.
  RouteManifest buildRouteManifest() {
    final validationRuleNames = <String>[];
    final routeEntries = getAllRoutes()
        .map(RouteManifestEntry.fromEngineRoute)
        .toList();
    final websocketEntries = debugWebSocketRoutes.entries
        .map(
          (entry) =>
              WebSocketRouteManifestEntry.fromRoute(entry.key, entry.value),
        )
        .toList();
    return RouteManifest(
      routes: routeEntries,
      webSockets: websocketEntries,
      validationRuleNames: validationRuleNames,
    );
  }
}

String _describeMiddleware(Object middleware) {
  final type = middleware.runtimeType.toString();
  if (type.isEmpty || type == 'dynamic') {
    return '<anonymous middleware>';
  }
  return type;
}

Map<String, Object?> _serializeMetadata(Map<String, Object?> source) {
  final result = <String, Object?>{};
  source.forEach((key, value) {
    final serialized = _serializeMetadataValue(value);
    if (serialized != null) result[key] = serialized;
  });
  return result;
}

Object? _serializeMetadataValue(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is Map) {
    final result = <String, Object?>{};
    value.forEach((key, nested) {
      final serialized = _serializeMetadataValue(nested);
      if (serialized != null) result[key.toString()] = serialized;
    });
    return result;
  }
  if (value is Iterable) {
    return value.map(_serializeMetadataValue).toList(growable: false);
  }
  try {
    final dynamic serializable = value;
    final json = serializable.toJson();
    return _serializeMetadataValue(json);
  } catch (_) {
    return value.toString();
  }
}

Map<String, Object?> _serializeConstraints(Map<String, dynamic> source) {
  if (source.isEmpty) return const {};
  final result = <String, Object?>{};
  source.forEach((key, value) {
    result[key] = _serializeConstraintValue(value);
  });
  return result;
}

Object? _serializeConstraintValue(Object? value) {
  if (value == null || value is num || value is bool || value is String) {
    return value;
  }
  if (value is Enum) {
    return value.name;
  }
  if (value is Iterable) {
    return value.map(_serializeConstraintValue).toList();
  }
  if (value is Map) {
    final serialized = <String, Object?>{};
    value.forEach((key, element) {
      serialized[key.toString()] = _serializeConstraintValue(element);
    });
    return serialized;
  }
  return value.runtimeType.toString();
}

Map<String, Object?> _stringKeyed(Map<Object?, Object?>? source) {
  if (source == null || source.isEmpty) return const <String, Object?>{};
  return source.map((key, value) => MapEntry(key?.toString() ?? '', value))
    ..removeWhere((key, _) => key.isEmpty);
}
