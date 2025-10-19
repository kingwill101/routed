import 'dart:convert';

import 'engine.dart';

/// A serializable snapshot of the engine's registered routes.
class RouteManifest {
  RouteManifest({
    DateTime? generatedAt,
    Iterable<RouteManifestEntry> routes = const [],
    Iterable<WebSocketRouteManifestEntry> webSockets = const [],
  }) : generatedAt = generatedAt ?? DateTime.now().toUtc(),
       routes = List<RouteManifestEntry>.unmodifiable(routes),
       webSockets = List<WebSocketRouteManifestEntry>.unmodifiable(webSockets);

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

    return RouteManifest(
      generatedAt: generatedAt,
      routes: routes,
      webSockets: webSockets,
    );
  }

  /// Timestamp (UTC) when the manifest was produced.
  final DateTime generatedAt;

  /// HTTP routes exposed by the engine.
  final List<RouteManifestEntry> routes;

  /// Registered WebSocket routes.
  final List<WebSocketRouteManifestEntry> webSockets;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'generatedAt': generatedAt.toIso8601String(),
      'routes': routes.map((route) => route.toJson()).toList(growable: false),
      'webSockets': webSockets
          .map((route) => route.toJson())
          .toList(growable: false),
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
  RouteManifestEntry({
    required this.method,
    required this.path,
    this.name,
    Iterable<String> middleware = const [],
    Map<String, Object?> constraints = const {},
    this.isFallback = false,
  }) : middleware = List<String>.unmodifiable(middleware),
       constraints = Map<String, Object?>.unmodifiable(constraints);

  factory RouteManifestEntry.fromEngineRoute(EngineRoute route) {
    return RouteManifestEntry(
      method: route.method,
      path: route.path,
      name: route.name,
      middleware: route.middlewares.map(_describeMiddleware),
      constraints: _serializeConstraints(route.constraints),
      isFallback: route.isFallback,
    );
  }

  factory RouteManifestEntry.fromJson(Map<String, Object?> json) {
    final method = json['method']?.toString() ?? 'GET';
    final path = json['path']?.toString() ?? '/';
    final name = json['name']?.toString();
    final middleware = json['middleware'] is List
        ? (json['middleware'] as List)
              .whereType<Object>()
              .map((value) => value.toString())
              .toList()
        : const <String>[];
    final constraints = json['constraints'] is Map
        ? _stringKeyed(json['constraints'] as Map)
        : const <String, Object?>{};
    final isFallback = json['isFallback'] == true;
    return RouteManifestEntry(
      method: method,
      path: path,
      name: name?.isEmpty == true ? null : name,
      middleware: middleware,
      constraints: constraints,
      isFallback: isFallback,
    );
  }

  final String method;
  final String path;
  final String? name;
  final List<String> middleware;
  final Map<String, Object?> constraints;
  final bool isFallback;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'method': method,
      'path': path,
      if (name != null) 'name': name,
      if (middleware.isNotEmpty) 'middleware': middleware,
      if (constraints.isNotEmpty) 'constraints': constraints,
      if (isFallback) 'isFallback': true,
    };
  }
}

/// Describes a WebSocket route in the manifest output.
class WebSocketRouteManifestEntry {
  WebSocketRouteManifestEntry({
    required this.path,
    Iterable<String> middleware = const [],
  }) : middleware = List<String>.unmodifiable(middleware);

  factory WebSocketRouteManifestEntry.fromRoute(
    String path,
    WebSocketEngineRoute route,
  ) {
    return WebSocketRouteManifestEntry(
      path: path,
      middleware: route.middlewares.map(_describeMiddleware),
    );
  }

  factory WebSocketRouteManifestEntry.fromJson(Map<String, Object?> json) {
    final path = json['path']?.toString() ?? '/';
    final middleware = json['middleware'] is List
        ? (json['middleware'] as List)
              .whereType<Object>()
              .map((value) => value.toString())
              .toList()
        : const <String>[];
    return WebSocketRouteManifestEntry(path: path, middleware: middleware);
  }

  final String path;
  final List<String> middleware;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'path': path,
      if (middleware.isNotEmpty) 'middleware': middleware,
    };
  }
}

extension EngineRouteManifestX on Engine {
  /// Generates a [RouteManifest] for the current engine.
  RouteManifest buildRouteManifest() {
    final routeEntries = getAllRoutes()
        .map(RouteManifestEntry.fromEngineRoute)
        .toList();
    final websocketEntries = debugWebSocketRoutes.entries
        .map(
          (entry) =>
              WebSocketRouteManifestEntry.fromRoute(entry.key, entry.value),
        )
        .toList();
    return RouteManifest(routes: routeEntries, webSockets: websocketEntries);
  }
}

String _describeMiddleware(Object middleware) {
  final type = middleware.runtimeType.toString();
  if (type.isEmpty || type == 'dynamic') {
    return '<anonymous middleware>';
  }
  return type;
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
