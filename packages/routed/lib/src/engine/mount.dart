part of 'engine.dart';

/// Data structure to store each "mount" of a Router in the Engine:
/// - prefix: e.g. `/v1`
/// - router: an instance of Router
/// - middlewares: extra engine-level middlewares applying to that mount
class _EngineMount {
  final String prefix;
  final Router router;
  final List<Middleware> middlewares;

  _EngineMount(this.prefix, this.router, this.middlewares);
}
