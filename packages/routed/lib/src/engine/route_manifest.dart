import 'package:routed/src/engine/engine.dart';
import 'package:routed/src/openapi/handler_identity.dart';
import 'package:routed/src/validation/validator.dart';
import 'package:routed_openapi/routed_openapi.dart'
    show RouteManifest, RouteManifestEntry, WebSocketRouteManifestEntry;

export 'package:routed_openapi/routed_openapi.dart'
    show RouteManifest, RouteManifestEntry, WebSocketRouteManifestEntry;

extension EngineRouteManifestX on Engine {
  /// Generates a [RouteManifest] for the current engine.
  RouteManifest buildRouteManifest() {
    final validationRuleNames = <String>[];
    if (container.has<ValidationRuleRegistry>()) {
      validationRuleNames.addAll(container.get<ValidationRuleRegistry>().names);
      validationRuleNames.sort();
    }
    final routeEntries = getAllRoutes()
        .map(_manifestEntryFromEngineRoute)
        .toList();
    final websocketEntries = debugWebSocketRoutes.entries
        .map(
          (entry) => _manifestEntryFromWebSocketRoute(entry.key, entry.value),
        )
        .toList();
    return RouteManifest(
      routes: routeEntries,
      webSockets: websocketEntries,
      validationRuleNames: validationRuleNames,
    );
  }
}

RouteManifestEntry _manifestEntryFromEngineRoute(EngineRoute route) {
  final handlerIdentity = HandlerIdentity(
    routeName: route.name,
    functionRef: _extractHandlerFunctionRef(route.handler),
    method: route.method,
    path: route.path,
    sourceFile: route.sourceFile,
    sourceLine: route.sourceLine,
    sourceColumn: route.sourceColumn,
  );

  return RouteManifestEntry(
    method: route.method,
    path: route.path,
    name: route.name,
    handlerIdentity: handlerIdentity.isResolved ? handlerIdentity : null,
    middleware: route.middlewares.map(_describeMiddleware),
    constraints: _serializeConstraints(route.constraints),
    isFallback: route.isFallback,
    schema: route.schema,
  );
}

WebSocketRouteManifestEntry _manifestEntryFromWebSocketRoute(
  String path,
  WebSocketEngineRoute route,
) {
  return WebSocketRouteManifestEntry(
    path: path,
    middleware: route.middlewares.map(_describeMiddleware),
  );
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

String? _extractHandlerFunctionRef(Object handler) {
  final text = handler.toString();

  final namedMatch = RegExp(r"Function '([^']+)'").firstMatch(text);
  var candidate = namedMatch?.group(1);
  if (candidate == null || candidate.isEmpty) {
    return null;
  }

  if (candidate.contains('<anonymous closure>')) {
    return null;
  }

  if (candidate.startsWith('new ')) {
    candidate = candidate.substring(4);
  }

  return candidate;
}
