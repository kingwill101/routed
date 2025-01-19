// lib/engine.dart
import 'router.dart';

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

/// The final route structure after combining everything:
/// - method, path, name
/// - middlewares: engine-level + route.finalMiddlewares
class EngineRoute {
  final String method;
  final String path;
  final String? name;
  final List<Middleware> middlewares;

  EngineRoute({
    required this.method,
    required this.path,
    this.name,
    this.middlewares = const [],
  });

  @override
  String toString() {
    final mwCount = middlewares.isEmpty ? 0 : middlewares.length;
    return '[$method] $path with name ${name ?? "(no name)"} [middlewares: $mwCount]';
  }
}

/// The Engine can mount multiple routers under different prefixes,
/// each with optional "engine-level" middlewares.
/// Then you call build() to produce a flattened route table.
class Engine {
  final List<_EngineMount> _mounts = [];
  final List<EngineRoute> _engineRoutes = [];

  /// Attach a router at a given prefix, with optional engine-level middlewares
  void use(
      String prefix,
      Router router, {
        List<Middleware> middlewares = const [],
      }) {
    _mounts.add(_EngineMount(prefix, router, middlewares));
  }

  /// Build the final route table:
  /// 1) For each mount, call `router.build()`
  /// 2) For each route in the router, merge with the prefix
  /// 3) Combine engine-level middlewares with the route's finalMiddlewares
  void build({String? parentGroupName}) {
    _engineRoutes.clear();

    for (final mount in _mounts) {
      // Let the child router finish its group & route merges
      mount.router.build(parentGroupName: parentGroupName);

      // Flatten all routes
      final childRoutes = mount.router.getAllRoutes();
      for (final r in childRoutes) {
        final combinedPath = _joinPaths(mount.prefix, r.path);

        // Engine-level + route's final
        final allMiddlewares = [...mount.middlewares, ...r.finalMiddlewares];

        _engineRoutes.add(
          EngineRoute(
            method: r.method,
            path: combinedPath,
            name: r.name,
            middlewares: allMiddlewares,
          ),
        );
      }
    }
  }

  /// Return all final routes
  List<EngineRoute> getAllRoutes() => List.unmodifiable(_engineRoutes);

  /// Print them
  void printRoutes() {
    for (final route in _engineRoutes) {
      print(route);
    }
  }

  // same path-join logic as the router
  static String _joinPaths(String base, String child) {
    if (base.isEmpty && child.isEmpty) return '';
    if (base.isEmpty) return child;
    if (child.isEmpty) return base;

    if (base.endsWith('/') && child.startsWith('/')) {
      return base + child.substring(1);
    } else if (!base.endsWith('/') && !child.startsWith('/')) {
      return '$base/$child';
    } else {
      return base + child;
    }
  }
}
