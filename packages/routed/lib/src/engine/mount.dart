part of 'engine.dart';

/// Data structure to store each "mount" of a Router in the Engine:
/// - prefix: e.g. `/v1`
/// - router: an instance of Router
/// - middlewares: extra engine-level middlewares applying to that mount
class _EngineMount {
  final String prefix;
  final Router router;
  final List<Middleware> middlewares;

  _EngineMount(this.prefix, this.router, List<Middleware> middlewares)
    : middlewares = List<Middleware>.from(middlewares);
}

class WebSocketEngineRoute {
  WebSocketEngineRoute({
    required this.path,
    required this.handler,
    required this.pattern,
    required this.paramInfo,
    required RoutePatternRegistry patternRegistry,
    List<Middleware>? middlewares,
    MiddlewareExclusions? exclusions,
  }) : _patternRegistry = patternRegistry,
       middlewares = List<Middleware>.from(middlewares ?? const []),
       exclusions = exclusions ?? MiddlewareExclusions();

  final String path;
  final RegExp pattern;
  final Map<String, ParamInfo> paramInfo;
  final WebSocketHandler handler;
  final List<Middleware> middlewares;
  final MiddlewareExclusions exclusions;
  final RoutePatternRegistry _patternRegistry;

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
