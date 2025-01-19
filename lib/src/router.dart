// lib/my_router.dart

/// Just a placeholder for a request/response handler.
typedef Handler = void Function(dynamic request, dynamic response);

/// A middleware is typically: (req, res, next) => ...
typedef Middleware = void Function(dynamic request, dynamic response, void Function() next);

/// Represents a single HTTP route, including:
/// - HTTP method (GET, POST, etc.)
/// - Path (e.g. `/api/books`)
/// - Name (e.g. `api.books.list`)
/// - The actual route handler
/// - A list of route-specific middlewares
///
/// We also include a field `finalMiddlewares` which is computed after build()
/// to capture the *full* chain (group + route).
class RegisteredRoute {
  final String method;
  final String path;
  String? name;
  final Handler handler;

  /// Middlewares specifically attached to this route
  final List<Middleware> routeMiddlewares;

  /// After calling `build()`, we store the *merged* middlewares here:
  /// (group-level + route-level)
  List<Middleware> finalMiddlewares = [];

  RegisteredRoute({
    required this.method,
    required this.path,
    required this.handler,
    this.name,
    this.routeMiddlewares = const [],
  });

  @override
  String toString() {
    final mw = finalMiddlewares.isEmpty
        ? ''
        : ' [middlewares: ${finalMiddlewares.length}]';
    return '[$method] $path with name ${name ?? "(no name)"}$mw';
  }
}

/// A hierarchical Router supporting:
/// - Sub-groups (which can each have path + middlewares)
/// - Multiple HTTP verbs
/// - Group-level middlewares
/// - Route-level middlewares
class Router {
  /// Base path for this router (e.g. `/api`)
  final String _prefix;

  /// Optional group name (e.g. `api`), for hierarchical naming.
  String? groupName;

  /// Middlewares for *this* group. All routes in this router & sub-routers inherit them.
  List<Middleware> groupMiddlewares = [];

  /// Direct routes defined at this level
  final List<RegisteredRoute> _routes = [];

  /// Sub-routers
  final List<Router> _children = [];

  /// Public getter so we can inspect direct routes if needed.
  List<RegisteredRoute> get routes => _routes;

  /// Constructor
  ///
  /// - [path]: base path (e.g. `/api`)
  /// - [groupName]: optional name (e.g. `api`)
  /// - [middlewares]: group-level middlewares for this router
  Router({
    String path = '',
    this.groupName,
    List<Middleware> middlewares = const [],
  }) : _prefix = path {
    groupMiddlewares.addAll(middlewares);
  }

  /// Create a sub-group (child router).
  ///
  /// - [path]: appended to this router’s path
  /// - [middlewares]: appended to this router’s `groupMiddlewares`
  /// - [builder]: function that configures the child router (routes, subgroups)
  RouterGroupBuilder group({
    String path = '',
    List<Middleware> middlewares = const [],
    required void Function(Router) builder,
  }) {
    final combinedPath = _joinPaths(_prefix, path);

    // Create child
    final child = Router(path: combinedPath);
    // Inherit *this* router's group-level middlewares + plus new ones
    child.groupMiddlewares = [...groupMiddlewares, ...middlewares];

    // Let the user define routes or subgroups
    builder(child);

    // Register child
    _children.add(child);

    // Return a builder for `.name("someName")`.
    return RouterGroupBuilder(child);
  }

  // ----------------
  //  HTTP VERBS
  // ----------------
  RouteBuilder get(String path, Handler handler, {List<Middleware> middlewares = const []}) {
    return _register("GET", path, handler, middlewares);
  }

  RouteBuilder post(String path, Handler handler, {List<Middleware> middlewares = const []}) {
    return _register("POST", path, handler, middlewares);
  }

  RouteBuilder put(String path, Handler handler, {List<Middleware> middlewares = const []}) {
    return _register("PUT", path, handler, middlewares);
  }

  RouteBuilder delete(String path, Handler handler, {List<Middleware> middlewares = const []}) {
    return _register("DELETE", path, handler, middlewares);
  }

  RouteBuilder patch(String path, Handler handler, {List<Middleware> middlewares = const []}) {
    return _register("PATCH", path, handler, middlewares);
  }

  RouteBuilder head(String path, Handler handler, {List<Middleware> middlewares = const []}) {
    return _register("HEAD", path, handler, middlewares);
  }

  RouteBuilder options(String path, Handler handler, {List<Middleware> middlewares = const []}) {
    return _register("OPTIONS", path, handler, middlewares);
  }

  RouteBuilder connect(String path, Handler handler, {List<Middleware> middlewares = const []}) {
    return _register("CONNECT", path, handler, middlewares);
  }
  // ----------------

  /// Internal helper to register any method
  RouteBuilder _register(
      String method,
      String path,
      Handler handler,
      List<Middleware> middlewares,
      ) {
    final fullPath = _joinPaths(_prefix, path);
    final route = RegisteredRoute(
      method: method,
      path: fullPath,
      handler: handler,
      routeMiddlewares: middlewares,
    );
    _routes.add(route);
    return RouteBuilder(route);
  }

  /// Build merges naming & middlewares:
  /// - [parentGroupName]: name from the parent (merged with `this.groupName`)
  /// - [inheritedMiddlewares]: the parent's combined group middlewares
  void build({
    String? parentGroupName,
    List<Middleware> inheritedMiddlewares = const [],
  }) {
    // Merge parent's group name with ours => effective name
    final effectiveGroupName = _joinNames(parentGroupName, groupName);

    // Merge parent's middlewares with ours
    final combinedMiddlewares = [...inheritedMiddlewares, ...groupMiddlewares];

    // Update routes
    for (final route in _routes) {
      // Merge route name
      if (route.name != null && route.name!.isNotEmpty) {
        route.name = _joinNames(effectiveGroupName, route.name);
      }
      // Merge route middlewares => group + route
      route.finalMiddlewares = [...combinedMiddlewares, ...route.routeMiddlewares];
    }

    // Recursively build children
    for (final child in _children) {
      child.build(
        parentGroupName: effectiveGroupName,
        inheritedMiddlewares: combinedMiddlewares,
      );
    }
  }

  /// Print all routes in the console.
  void printRoutes() {
    for (final route in getAllRoutes()) {
      print(route);
    }
  }

  /// Return flattened list of routes
  List<RegisteredRoute> getAllRoutes() {
    final results = <RegisteredRoute>[];
    results.addAll(_routes);
    for (final c in _children) {
      results.addAll(c.getAllRoutes());
    }
    return results;
  }

  // ---------------------------
  //  Utility path/name joiners
  // ---------------------------
  static String _joinPaths(String base, String child) {
    if (base.isEmpty && child.isEmpty) return '';
    if (base.isEmpty) return child;
    if (child.isEmpty) return base;

    if (base.endsWith('/') && child.startsWith('/')) {
      return base + child.substring(1); // remove double slash
    } else if (!base.endsWith('/') && !child.startsWith('/')) {
      return '$base/$child';
    } else {
      return base + child;
    }
  }

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

/// Returned by `router.get(...)` etc., so you can do `.name("routeName")`.
class RouteBuilder {
  final RegisteredRoute _route;
  RouteBuilder(this._route);

  RouteBuilder name(String routeName) {
    _route.name = routeName;
    return this;
  }
}
