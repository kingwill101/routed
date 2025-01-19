// lib/my_router.dart

/// Placeholder for the request/response handler type.
typedef Handler = void Function(dynamic request, dynamic response);

/// Represents a single HTTP route (e.g. GET /users).
class RegisteredRoute {
  final String method;
  final String path;
  String? name;
  final Handler handler;

  RegisteredRoute({
    required this.method,
    required this.path,
    required this.handler,
    this.name,
  });

  @override
  String toString() =>
      '[$method] $path with name ${name ?? "(no name)"}';
}

/// A simple hierarchical Router with all major HTTP verbs.
class Router {
  /// The path prefix for this router (e.g. `/api`)
  final String _prefix;

  /// Optional group name for hierarchical naming
  String? groupName;

  /// Direct routes in this router
  final List<RegisteredRoute> _routes = [];

  /// Child routers
  final List<Router> _children = [];

  /// Public getter so tests or merges can inspect routes
  List<RegisteredRoute> get routes => _routes;

  Router({
    String path = '',
    this.groupName,
  }) : _prefix = path;

  /// Create a nested group of routes, with its own path and potential name.
  RouterGroupBuilder group({
    String path = '',
    required void Function(Router) builder,
  }) {
    final combinedPath = _joinPaths(_prefix, path);
    final child = Router(path: combinedPath);
    builder(child);
    _children.add(child);
    return RouterGroupBuilder(child);
  }

  // ---------------------
  //  All HTTP Verbs
  // ---------------------
  RouteBuilder get(String path, Handler handler) {
    return _register("GET", path, handler);
  }

  RouteBuilder post(String path, Handler handler) {
    return _register("POST", path, handler);
  }

  RouteBuilder put(String path, Handler handler) {
    return _register("PUT", path, handler);
  }

  RouteBuilder delete(String path, Handler handler) {
    return _register("DELETE", path, handler);
  }

  RouteBuilder patch(String path, Handler handler) {
    return _register("PATCH", path, handler);
  }

  RouteBuilder head(String path, Handler handler) {
    return _register("HEAD", path, handler);
  }

  RouteBuilder options(String path, Handler handler) {
    return _register("OPTIONS", path, handler);
  }

  RouteBuilder connect(String path, Handler handler) {
    return _register("CONNECT", path, handler);
  }
  // ---------------------

  /// Internal helper to register any method
  RouteBuilder _register(String method, String path, Handler handler) {
    final fullPath = _joinPaths(_prefix, path);
    final route = RegisteredRoute(
      method: method,
      path: fullPath,
      handler: handler,
    );
    _routes.add(route);
    return RouteBuilder(route);
  }

  /// Build hierarchical naming
  void build({String? parentGroupName}) {
    final effectiveGroupName = _joinNames(parentGroupName, groupName);

    // update direct routes
    for (final route in _routes) {
      if (route.name != null && route.name!.isNotEmpty) {
        route.name = _joinNames(effectiveGroupName, route.name);
      }
    }

    // recursively build children
    for (final child in _children) {
      child.build(parentGroupName: effectiveGroupName);
    }
  }

  /// Print all routes (this router + all descendants).
  void printRoutes() {
    for (final route in getAllRoutes()) {
      print('[${route.method}] ${route.path} with name ${route.name}');
    }
  }

  /// Flatten all routes (this router + all descendants).
  List<RegisteredRoute> getAllRoutes() {
    final results = <RegisteredRoute>[];
    results.addAll(_routes);
    for (final c in _children) {
      results.addAll(c.getAllRoutes());
    }
    return results;
  }

  /// Combine two path segments without double slashes
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

  /// Merge parent and child names with a dot
  static String _joinNames(String? parent, String? child) {
    if (parent == null || parent.isEmpty) return child ?? '';
    if (child == null || child.isEmpty) return parent;
    return '$parent.$child';
  }
}

/// Allows chaining `.name("groupName")` after `router.group(...)`.
class RouterGroupBuilder {
  final Router _router;
  RouterGroupBuilder(this._router);

  RouterGroupBuilder name(String groupName) {
    _router.groupName = groupName;
    return this;
  }
}

/// Allows chaining `.name("routeName")` after registering a route
/// (e.g. `router.get('/path', handler).name('myRoute')`).
class RouteBuilder {
  final RegisteredRoute _route;
  RouteBuilder(this._route);

  RouteBuilder name(String routeName) {
    _route.name = routeName;
    return this;
  }
}
