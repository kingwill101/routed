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
    List<Middleware>? middlewares,
  }) : middlewares = List<Middleware>.from(middlewares ?? const []);

  final String path;
  final WebSocketHandler handler;
  final List<Middleware> middlewares;
}
