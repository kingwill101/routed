/// Just a placeholder for the request/response handler type.
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

/// A simple hierarchical Router.
class Router {
  /// The path prefix for this router (e.g. `/api`)
  final String _prefix;

  /// The "group" name (used for naming routes).
  String? groupName;

  /// Direct routes defined at this router level.
  final List<RegisteredRoute> _routes = [];

  /// Child routers (subgroups).
  final List<Router> _children = [];

  /// Public getter so tests can inspect routes directly if needed.
  List<RegisteredRoute> get routes => _routes;

  /// [path]: The base path for this router. e.g. `/api`.
  /// [groupName]: Optional name for this group (e.g. `api`).
  Router({
    String path = '',
    this.groupName,
  }) : _prefix = path;

  /// Create a subgroup (child Router).
  ///
  /// - [path]: sub-path to append to `_prefix`.
  /// - [builder]: function that configures the child router (adding routes, etc.).
  RouterGroupBuilder group({
    String path = '',
    required void Function(Router) builder,
  }) {
    final combinedPath = _joinPaths(_prefix, path);

    // Create a child router and let the caller configure it.
    final child = Router(path: combinedPath);
    builder(child);

    // Store child so we can include it in the final build.
    _children.add(child);

    // Return a builder so you can do `.name("something")`.
    return RouterGroupBuilder(child);
  }

  // -----------------------------------------------
  //  Common HTTP Methods
  // -----------------------------------------------
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
  // -----------------------------------------------

  /// Internal helper to register a route of any method
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

  /// Finalize route names by combining each route's `name` with our parent's name.
  ///
  /// Call this after all groups/routes are registered (e.g. before printing or using them).
  void build({String? parentGroupName}) {
    // Merge parent name + our own name => effective name
    final effectiveGroupName = _joinNames(parentGroupName, groupName);

    // Update direct routes
    for (final route in _routes) {
      if (route.name != null && route.name!.isNotEmpty) {
        route.name = _joinNames(effectiveGroupName, route.name);
      }
    }

    // Recursively build children, passing our effectiveGroupName.
    for (final child in _children) {
      child.build(parentGroupName: effectiveGroupName);
    }
  }

  /// Print all routes to the console.
  void printRoutes() {
    final all = getAllRoutes();
    for (final route in all) {
      print('[${route.method}] ${route.path} with name ${route.name}');
    }
  }

  /// Gather this router’s routes plus all descendants.
  List<RegisteredRoute> getAllRoutes() {
    final results = <RegisteredRoute>[];
    results.addAll(_routes);
    for (final c in _children) {
      results.addAll(c.getAllRoutes());
    }
    return results;
  }

  /// A helper to join path segments without double slashes.
  static String _joinPaths(String base, String child) {
    if (base.isEmpty && child.isEmpty) {
      return '';
    }
    if (base.isEmpty) {
      return child; // e.g. '' + '/api' => '/api'
    }
    if (child.isEmpty) {
      return base; // e.g. '/api' + '' => '/api'
    }

    // Both are non-empty
    // - If base ends with '/', and child starts with '/', remove one to avoid `//`.
    if (base.endsWith('/') && child.startsWith('/')) {
      return base + child.substring(1);
    } else if (!base.endsWith('/') && !child.startsWith('/')) {
      // If neither has a slash, add one
      return '$base/$child';
    } else {
      // Exactly one slash is present, so just concatenate
      return base + child;
    }
  }

  /// Joins parent name and child name with a dot, e.g. `"api" + "books" = "api.books"`.
  static String _joinNames(String? parent, String? child) {
    if (parent == null || parent.isEmpty) return child ?? '';
    if (child == null || child.isEmpty) return parent;
    return '$parent.$child';
  }
}

/// Returned by `router.group(...)` so you can do `.name("myGroup")`.
class RouterGroupBuilder {
  final Router _router;
  RouterGroupBuilder(this._router);

  RouterGroupBuilder name(String groupName) {
    _router.groupName = groupName;
    return this;
  }
}

/// Returned by `router.get(...)`, `router.post(...)`, etc. so you can do `.name("myRoute")`.
class RouteBuilder {
  final RegisteredRoute _route;
  RouteBuilder(this._route);

  RouteBuilder name(String routeName) {
    _route.name = routeName;
    return this;
  }
}
