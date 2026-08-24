part of 'engine.dart';

/// Data structure to store each "mount" of a Router in the Engine:
/// - prefix: e.g. `/v1`
/// - router: an instance of Router
/// - middlewares: extra engine-level middlewares applying to that mount
class _EngineMount {
  _EngineMount(this.prefix, this.router, List<Middleware> middlewares)
    : middlewares = List<Middleware>.from(middlewares);
  final String prefix;
  final Router router;
  final List<Middleware> middlewares;
}

/// A compiled WebSocket route held by the engine.
class WebSocketEngineRoute {
  /// Creates a WebSocket route from its compiled [pattern] and metadata.
  WebSocketEngineRoute({
    required this.path,
    required this.handler,
    required this.pattern,
    required this.paramInfo,
    required RoutePatternRegistry patternRegistry,
    List<Middleware>? middlewares,
  }) : _patternRegistry = patternRegistry,
       middlewares = List<Middleware>.from(middlewares ?? const []);

  /// The route path pattern as registered by the application.
  final String path;

  /// The compiled expression used to match request paths.
  final RegExp pattern;

  /// Metadata for parameters captured by [pattern].
  final Map<String, ParamInfo> paramInfo;

  /// The handler invoked after a WebSocket upgrade.
  final WebSocketHandler handler;

  /// Middleware applied before [handler].
  final List<Middleware> middlewares;
  final RoutePatternRegistry _patternRegistry;

  /// Extracts and casts parameters from [uri].
  Map<String, dynamic> extractParameters(String uri) {
    final match = pattern.firstMatch(uri) ?? pattern.firstMatch('$uri/');
    if (match == null) return const {};

    return paramInfo.map((key, info) {
      final rawValue = match.namedGroup(key);
      if (rawValue == null && !info.isOptional) {
        return MapEntry(key, null);
      }

      String? decodedValue;
      if (rawValue != null) {
        try {
          decodedValue = Uri.decodeComponent(rawValue);
        } catch (_) {
          decodedValue = rawValue;
        }
      }

      return MapEntry(key, _patternRegistry.cast(decodedValue, info.type));
    });
  }
}
