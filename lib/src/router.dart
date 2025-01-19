/// Just a placeholder for a request/response handler.
typedef Handler = void Function(dynamic request, dynamic response);

/// A middleware is typically: (req, res, next) => ...
typedef Middleware = void Function(dynamic request, dynamic response, void Function() next);

/// Represents a single HTTP route, including:
/// - HTTP method
/// - Path
/// - Name (e.g. `api.books.list`)
/// - The actual route handler
/// - A list of route-level middlewares
///
/// After building, we store the *merged* middlewares in [finalMiddlewares].
class RegisteredRoute {
  final String method;
  final String path;
  String? name;
  final Handler handler;

  /// Middlewares specifically attached to this route
  final List<Middleware> routeMiddlewares;

  /// After `build()`, this holds the entire chain:
  /// (inherited group-level MW + route-level MW).
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
    final mwCount = finalMiddlewares.isEmpty ? 0 : finalMiddlewares.length;
    return '[$method] $path with name ${name ?? "(no name)"} [middlewares: $mwCount]';
  }
}

/// A hierarchical Router supporting:
/// - Sub-groups (each can have path + middlewares)
/// - Multiple HTTP verbs
/// - Group-level middlewares
/// - Route-level middlewares
/// - Hierarchical naming
class Router {
  /// Base path for this router (e.g. `/api`)
  final String _prefix;

  /// Optional group name (e.g. `api`)
  String? groupName;

  /// Middlewares *declared for this router group only*.
  /// (We do not manually copy the parent's middlewares here.)
  final List<Middleware> groupMiddlewares = [];

  /// Direct routes defined at this level
  final List<RegisteredRoute> _routes = [];

  /// Child routers
  final List<Router> _children = [];

  /// Public getter so tests or merges can inspect routes.
  List<RegisteredRoute> get routes => _routes;

  /// Constructor
  ///
  /// [path]: base path for this router, e.g. `/api`
  /// [groupName]: optional name for hierarchical naming, e.g. `api`
  /// [middlewares]: group-level middlewares declared for *this* router
  Router({
    String path = '',
    this.groupName,
    List<Middleware> middlewares = const [],
  }) : _prefix = path {
    // We store only the *new* middlewares declared for this router.
    groupMiddlewares.addAll(middlewares);
  }

  /// Create a sub-group (child router).
  ///
  /// [path]: appended to this router’s path
  /// [middlewares]: new middlewares for this child group
  /// [builder]: configures the child (adding routes, subgroups)
  ///
  /// We do *not* copy the parent's middlewares here; that will be merged in [build()].
  RouterGroupBuilder group({
    String path = '',
    List<Middleware> middlewares = const [],
    required void Function(Router) builder,
  }) {
    final combinedPath = _joinPaths(_prefix, path);

    // Child has only its newly declared middlewares
    final child = Router(path: combinedPath, middlewares: middlewares);

    // Let the user define routes/subgroups on the child
    builder(child);

    // Attach child to our children
    _children.add(child);

    // Return a builder so we can do `.name("someGroup")`.
    return RouterGroupBuilder(child);
  }

  // ----------------
  //  HTTP Methods
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

  /// Internal helper to create and store a [RegisteredRoute].
  RouteBuilder _register(
      String method,
      String path,
      Handler handler,
      List<Middleware> routeMW,
      ) {
    final fullPath = _joinPaths(_prefix, path);
    final route = RegisteredRoute(
      method: method,
      path: fullPath,
      handler: handler,
      routeMiddlewares: routeMW,
    );
    _routes.add(route);
    return RouteBuilder(route);
  }

  /// Build merges naming & middlewares.
  ///
  /// [parentGroupName]: parent's group name for hierarchical naming
  /// [inheritedMiddlewares]: parent's middlewares so far
  ///
  /// The final route middlewares = inherited + groupMiddlewares + route-specific
  void build({
    String? parentGroupName,
    List<Middleware> inheritedMiddlewares = const [],
  }) {
    // Combine parent's name and ours => effective name
    final effectiveGroupName = _joinNames(parentGroupName, groupName);

    // Merge parent's middlewares + ours
    final combinedMW = [...inheritedMiddlewares, ...groupMiddlewares];

    // Update direct routes
    for (final route in _routes) {
      // Merge route name
      if (route.name != null && route.name!.isNotEmpty) {
        route.name = _joinNames(effectiveGroupName, route.name);
      }
      // Merge route-level middlewares
      route.finalMiddlewares = [...combinedMW, ...route.routeMiddlewares];
    }

    // Recursively build children
    for (final child in _children) {
      child.build(
        parentGroupName: effectiveGroupName,
        inheritedMiddlewares: combinedMW,
      );
    }
  }

  /// Print all routes in this router + sub-routers to console.
  void printRoutes() {
    for (final route in getAllRoutes()) {
      print(route);
    }
  }

  /// Flatten all routes (this router + children + deeper descendants)
  List<RegisteredRoute> getAllRoutes() {
    final results = <RegisteredRoute>[];
    results.addAll(_routes);
    for (final c in _children) {
      results.addAll(c.getAllRoutes());
    }
    return results;
  }

  // --------------------------------------------------
  // Utility path & name joiners
  // --------------------------------------------------
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
