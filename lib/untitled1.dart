// lib/my_router.dart
typedef Handler = void Function(dynamic request, dynamic response);

/// Represents a single HTTP route (e.g. GET /users/)
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
  // Current router's base path:
  final String _prefix;

  // Current router's group name:
  String? groupName;

  // Direct routes in this router
  final List<RegisteredRoute> _routes = [];

  // Child routers (subgroups)
  final List<Router> _children = [];

  /// Public getter so you can inspect routes in tests
  List<RegisteredRoute> get routes => _routes;

  Router({
    String path = '',
    this.groupName,
  }) : _prefix = _normalizeSlashes(path);

  /// Create a sub-group (which is itself a Router).
  ///
  /// - [path] is appended to this router's prefix.
  /// - [builder] configures the sub-router.
  RouterGroupBuilder group({
    String path = '',
    required void Function(Router) builder,
  }) {
    final child = Router(
      path: _joinPaths(_prefix, path),
    );
    _children.add(child);

    // Let the caller define routes or subgroups within [child].
    builder(child);

    // Return a builder so we can `.name("someName")` for the group
    return RouterGroupBuilder(child);
  }

  /// Register a GET route
  RouteBuilder get(String path, Handler handler) {
    final route = RegisteredRoute(
      method: 'GET',
      path: _joinPaths(_prefix, path),
      handler: handler,
    );
    _routes.add(route);
    return RouteBuilder(route);
  }

  /// Once we've set up all groups/routes, we call build() to finalize name scopes.
  void build({String? parentGroupName}) {
    // Combine parent's group name with this router's own groupName.
    final currentGroupName = _joinNames(parentGroupName, groupName);

    // Update all direct routes, prefixing route names with our group name
    for (final route in _routes) {
      if (route.name != null) {
        route.name = _joinNames(currentGroupName, route.name);
      }
    }

    // Recursively build children
    for (final child in _children) {
      // If we (the parent) have a name, pass it to child
      child._inheritGroupName(currentGroupName);
      child.build(parentGroupName: currentGroupName);
    }
  }

  /// Print all routes (including descendants)
  void printRoutes() {
    final all = getAllRoutes();
    for (final route in all) {
      print('[${route.method}] ${route.path} with name ${route.name}');
    }
  }

  /// Return all routes (this router + descendants)
  List<RegisteredRoute> getAllRoutes() {
    final results = <RegisteredRoute>[];
    results.addAll(_routes);
    for (final c in _children) {
      results.addAll(c.getAllRoutes());
    }
    return results;
  }

  // Make a child inherit the parent's final group name.
  void _inheritGroupName(String? parentName) {
    // If parent doesn't have a name, no effect
    if (parentName == null || parentName.isEmpty) return;

    // If this router has a group name, combine them; else just use parent's
    if (groupName != null && groupName!.isNotEmpty) {
      groupName = _joinNames(parentName, groupName);
    } else {
      groupName = parentName;
    }
  }

  /// Utility: join two path segments with a single slash
  static String _joinPaths(String base, String part) {
    final b = _normalizeSlashes(base);
    final p = _normalizeSlashes(part);
    if (b.isEmpty && p.isEmpty) return '';
    if (b.isEmpty) return '/$p';
    if (p.isEmpty) return b;
    return '$b/$p';
  }

  /// Utility: ensure a path has no trailing slash (unless it's just "/")
  static String _normalizeSlashes(String s) {
    if (s.isEmpty) return '';
    // remove trailing slash, except if it's just "/"
    if (s != '/' && s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    // ensure leading slash
    if (!s.startsWith('/')) {
      s = '/$s';
    }
    // if it's just "/", normalize to '' so we don't double slash
    return s == '/' ? '' : s;
  }

  /// Utility: join parent name and child name with a dot.
  /// If either is empty or null, return the other.
  static String _joinNames(String? parent, String? child) {
    if (parent == null || parent.isEmpty) return child ?? '';
    if (child == null || child.isEmpty) return parent;
    return '$parent.$child';
  }
}

/// Lets you do `.name("myGroupName")` after calling `group(...)`.
class RouterGroupBuilder {
  final Router _router;
  RouterGroupBuilder(this._router);

  RouterGroupBuilder name(String n) {
    _router.groupName = n;
    return this;
  }
}

/// Lets you do `.name("myRouteName")` after calling `get(...)`.
class RouteBuilder {
  final RegisteredRoute _route;
  RouteBuilder(this._route);

  RouteBuilder name(String routeName) {
    _route.name = routeName;
    return this;
  }
}
