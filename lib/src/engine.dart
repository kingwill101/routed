// lib/engine.dart
import 'router.dart';
/// Minimal signature for a middleware
/// e.g.: (req, res, next) => ...
typedef Middleware = void Function(dynamic req, dynamic res, dynamic next);

/// Data structure that holds a single "mount":
/// - prefix: the base path for the sub-router
/// - router: the instance of the Router
/// - middlewares: an optional list of middlewares
class _EngineMount {
  final String prefix;
  final Router router;
  final List<Middleware> middlewares;
  _EngineMount(this.prefix, this.router, this.middlewares);
}

/// Data structure for the final "flattened" route after build:
/// It includes the final method, path, name, and any middlewares associated.
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
    final mwNames = middlewares.isEmpty
        ? ''
        : ' [middlewares: ${middlewares.length}]';
    return '[$method] $path with name ${name ?? "(no name)"}$mwNames';
  }
}

/// The "Engine" that can mount multiple routers at different prefixes
/// and optionally apply middlewares.
class Engine {
  final List<_EngineMount> _mounts = [];

  /// Mounts a `router` at a given `prefix`.
  /// Optionally pass in middlewares that should apply to all routes from that router.
  void use(
      String prefix,
      Router router, {
        List<Middleware> middlewares = const [],
      }) {
    _mounts.add(_EngineMount(prefix, router, middlewares));
  }

  /// "Build" merges all routers' routes into a single route table,
  /// applying the path prefix from each mount, as well as the parent's groupName.
  ///
  /// If you want route name merging across the entire engine, you can pass
  /// `parentGroupName` here. Or just rely on each router's `router.build()`.
  ///
  /// In this example, we do:
  /// 1. Build each router so it merges its own groupName hierarchy.
  /// 2. Then combine them into `_engineRoutes`, prefixing their paths and
  ///    storing any middlewares.
  final List<EngineRoute> _engineRoutes = [];
  void build({String? parentGroupName}) {
    _engineRoutes.clear();

    for (final mount in _mounts) {
      // 1) Build the child router so it finalizes naming
      mount.router.build(parentGroupName: parentGroupName);

      // 2) For each route in the child router, create an EngineRoute
      for (final r in mount.router.getAllRoutes()) {
        // Combine the mount prefix with the route's path
        final combinedPath = _joinPaths(mount.prefix, r.path);
        _engineRoutes.add(
          EngineRoute(
            method: r.method,
            path: combinedPath,
            name: r.name,
            middlewares: mount.middlewares,
          ),
        );
      }
    }
  }

  /// Return the final flattened route set after build
  List<EngineRoute> getAllRoutes() {
    return List.unmodifiable(_engineRoutes);
  }

  /// Print them in console
  void printRoutes() {
    for (final route in _engineRoutes) {
      print(route.toString());
    }
  }

  // A helper to combine the engine "mount prefix" with the child's route path
  // without double slashes.
  static String _joinPaths(String base, String child) {
    if (base.isEmpty && child.isEmpty) return '';
    if (base.isEmpty) return child;
    if (child.isEmpty) return base;

    // If both are non-empty, watch out for slash duplication
    if (base.endsWith('/') && child.startsWith('/')) {
      return base + child.substring(1);
    } else if (!base.endsWith('/') && !child.startsWith('/')) {
      return '$base/$child';
    } else {
      return base + child;
    }
  }
}
