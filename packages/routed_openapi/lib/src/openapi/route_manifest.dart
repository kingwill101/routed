import 'dart:convert';

import 'handler_identity.dart';
import 'schema.dart';

/// A serializable snapshot of the engine's registered routes.
class RouteManifest {
  RouteManifest({
    DateTime? generatedAt,
    Iterable<RouteManifestEntry> routes = const [],
    Iterable<WebSocketRouteManifestEntry> webSockets = const [],
    Iterable<String> validationRuleNames = const [],
  }) : generatedAt = generatedAt ?? DateTime.now().toUtc(),
       routes = List<RouteManifestEntry>.unmodifiable(routes),
       webSockets = List<WebSocketRouteManifestEntry>.unmodifiable(webSockets),
       validationRuleNames = List<String>.unmodifiable(validationRuleNames);

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
  RouteManifestEntry({
    required this.method,
    required this.path,
    this.name,
    this.handlerIdentity,
    Iterable<String> middleware = const [],
    Map<String, Object?> constraints = const {},
    this.isFallback = false,
    this.schema,
  }) : middleware = List<String>.unmodifiable(middleware),
       constraints = Map<String, Object?>.unmodifiable(constraints);

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
    final handlerIdentity = json['handlerIdentity'] is Map
        ? HandlerIdentity.fromJson(_stringKeyed(json['handlerIdentity'] as Map))
        : null;
    final schema = json['schema'] is Map
        ? RouteSchema.fromJson(_stringKeyed(json['schema'] as Map))
        : null;
    return RouteManifestEntry(
      method: method,
      path: path,
      name: name?.isEmpty == true ? null : name,
      handlerIdentity: handlerIdentity,
      middleware: middleware,
      constraints: constraints,
      isFallback: isFallback,
      schema: schema,
    );
  }

  final String method;
  final String path;
  final String? name;
  final HandlerIdentity? handlerIdentity;
  final List<String> middleware;
  final Map<String, Object?> constraints;
  final bool isFallback;

  /// Optional API schema metadata for this route.
  final RouteSchema? schema;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'method': method,
      'path': path,
      if (name != null) 'name': name,
      if (handlerIdentity != null) 'handlerIdentity': handlerIdentity!.toJson(),
      if (middleware.isNotEmpty) 'middleware': middleware,
      if (constraints.isNotEmpty) 'constraints': constraints,
      if (isFallback) 'isFallback': true,
      if (schema != null) 'schema': schema!.toJson(),
    };
  }
}

/// Describes a WebSocket route in the manifest output.
class WebSocketRouteManifestEntry {
  WebSocketRouteManifestEntry({
    required this.path,
    Iterable<String> middleware = const [],
  }) : middleware = List<String>.unmodifiable(middleware);

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

Map<String, Object?> _stringKeyed(Map<Object?, Object?>? source) {
  if (source == null || source.isEmpty) return const <String, Object?>{};
  return source.map((key, value) => MapEntry(key?.toString() ?? '', value))
    ..removeWhere((key, _) => key.isEmpty);
}
