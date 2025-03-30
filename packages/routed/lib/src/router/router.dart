import 'package:routed/routed.dart';
import 'package:routed/src/router/registered_route.dart';
import 'package:routed/src/router/route_builder.dart';
import 'package:routed/src/router/router_group_builder.dart';
import 'package:routed/src/static_files.dart';

/// A hierarchical Router supporting:
/// - Sub-groups (each can have path + middlewares)
/// - Multiple HTTP verbs
/// - Group-level middlewares
/// - Route-level middlewares
/// - Hierarchical naming
class Router with StaticFileHandler {
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
    void Function(Router)? builder,
  }) {
    final combinedPath = _joinPaths(_prefix, path);

    // Child has only its newly declared middlewares
    final child = Router(path: combinedPath, middlewares: middlewares);
    // Let the user define routes/subgroups on the child
    if (builder != null) builder(child);

    // Attach child to our children
    _children.add(child);

    // Return a builder so we can do `.name("someGroup")`.
    return RouterGroupBuilder(child);
  }

  /// Registers a fallback route with the router.
  ///
  /// [handler]: The handler function for the fallback route.
  /// [middlewares]: Optional middlewares specific to this fallback route.
  RouteBuilder fallback(Handler handler,
      {List<Middleware> middlewares = const []}) {
    final route = RegisteredRoute(
      method: '*',
      path: '/{__fallback:*}',
      handler: handler,
      routeMiddlewares: middlewares,
      constraints: {'isFallback': true},
    );
    _routes.add(route);
    return RouteBuilder(route, this);
  }

  // ----------------
  //  HTTP Methods
  // ----------------

  /// Registers a GET route with the router.
  ///
  /// [path]: The path for the GET route.
  /// [handler]: The handler function for the GET route.
  /// [middlewares]: Optional middlewares specific to this route.
  /// [constraints]: Optional constraints for the route parameters.
  RouteBuilder get(String path, Handler handler,
      {List<Middleware> middlewares = const [],
      Map<String, dynamic> constraints = const {}}) {
    return handle("GET", path, handler,
        middlewares: middlewares, constraints: constraints);
  }

  /// Registers a POST route with the router.
  ///
  /// [path]: The path for the POST route.
  /// [handler]: The handler function for the POST route.
  /// [middlewares]: Optional middlewares specific to this route.
  /// [constraints]: Optional constraints for the route parameters.
  RouteBuilder post(String path, Handler handler,
      {List<Middleware> middlewares = const [],
      Map<String, dynamic> constraints = const {}}) {
    return handle("POST", path, handler,
        middlewares: middlewares, constraints: constraints);
  }

  /// Registers a PUT route with the router.
  ///
  /// [path]: The path for the PUT route.
  /// [handler]: The handler function for the PUT route.
  /// [middlewares]: Optional middlewares specific to this route.
  /// [constraints]: Optional constraints for the route parameters.
  RouteBuilder put(String path, Handler handler,
      {List<Middleware> middlewares = const [],
      Map<String, dynamic> constraints = const {}}) {
    return handle("PUT", path, handler,
        middlewares: middlewares, constraints: constraints);
  }

  /// Registers a DELETE route with the router.
  ///
  /// [path]: The path for the DELETE route.
  /// [handler]: The handler function for the DELETE route.
  /// [middlewares]: Optional middlewares specific to this route.
  /// [constraints]: Optional constraints for the route parameters.
  RouteBuilder delete(String path, Handler handler,
      {List<Middleware> middlewares = const [],
      Map<String, dynamic> constraints = const {}}) {
    return handle("DELETE", path, handler,
        middlewares: middlewares, constraints: constraints);
  }

  /// Registers a PATCH route with the router.
  ///
  /// [path]: The path for the PATCH route.
  /// [handler]: The handler function for the PATCH route.
  /// [middlewares]: Optional middlewares specific to this route.
  /// [constraints]: Optional constraints for the route parameters.
  RouteBuilder patch(String path, Handler handler,
      {List<Middleware> middlewares = const [],
      Map<String, dynamic> constraints = const {}}) {
    return handle("PATCH", path, handler,
        middlewares: middlewares, constraints: constraints);
  }

  /// Registers a HEAD route with the router.
  ///
  /// [path]: The path for the HEAD route.
  /// [handler]: The handler function for the HEAD route.
  /// [middlewares]: Optional middlewares specific to this route.
  /// [constraints]: Optional constraints for the route parameters.
  RouteBuilder head(String path, Handler handler,
      {List<Middleware> middlewares = const [],
      Map<String, dynamic> constraints = const {}}) {
    return handle("HEAD", path, handler,
        middlewares: middlewares, constraints: constraints);
  }

  /// Registers an OPTIONS route with the router.
  ///
  /// [path]: The path for the OPTIONS route.
  /// [handler]: The handler function for the OPTIONS route.
  /// [middlewares]: Optional middlewares specific to this route.
  /// [constraints]: Optional constraints for the route parameters.
  RouteBuilder options(String path, Handler handler,
      {List<Middleware> middlewares = const [],
      Map<String, dynamic> constraints = const {}}) {
    return handle("OPTIONS", path, handler,
        middlewares: middlewares, constraints: constraints);
  }

  /// Registers a CONNECT route with the router.
  ///
  /// [path]: The path for the CONNECT route.
  /// [handler]: The handler function for the CONNECT route.
  /// [middlewares]: Optional middlewares specific to this route.
  /// [constraints]: Optional constraints for the route parameters.
  RouteBuilder connect(String path, Handler handler,
      {List<Middleware> middlewares = const [],
      Map<String, dynamic> constraints = const {}}) {
    return handle("CONNECT", path, handler,
        middlewares: middlewares, constraints: constraints);
  }

  // ----------------

  /// Internal helper to create and store a [RegisteredRoute].
  ///
  /// [method]: The HTTP method for the route (e.g., GET, POST).
  /// [path]: The path for the route.
  /// [handler]: The handler function for the route.
  /// [middlewares]: Optional middlewares specific to this route.
  /// [constraints]: Optional constraints for the route parameters.
  RouteBuilder handle(
    String method,
    String path,
    Handler handler, {
    List<Middleware> middlewares = const [],
    Map<String, dynamic> constraints = const {},
  }) {
    final fullPath = _joinPaths(_prefix, path);
    final route = RegisteredRoute(
      method: method,
      path: fullPath,
      handler: handler,
      routeMiddlewares: middlewares,
      constraints: constraints,
    );
    _routes.add(route);
    return RouteBuilder(route, this);
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
    String parentPrefix = '', // Add this parameter
  }) {
    // Combine parent's name and ours => effective name
    final effectiveGroupName = _joinNames(parentGroupName, groupName);

    // Combine parent's middlewares and ours
    final combinedMW = [...inheritedMiddlewares, ...groupMiddlewares];

    // Update direct routes
    for (final route in _routes) {
      // Merge route name
      if (route.name != null && route.name!.isNotEmpty) {
        route.name = _joinNames(effectiveGroupName, route.name);
      }
      // Merge route-level middlewares
      route.finalMiddlewares = [...combinedMW, ...route.routeMiddlewares];
      if (!route.path.startsWith(_prefix)) {
        route.path = _joinPaths(_prefix, route.path);
      }
    }

    // Recursively build children
    for (final child in _children) {
      child.build(
        parentGroupName: effectiveGroupName,
        inheritedMiddlewares: combinedMW,
        parentPrefix: _joinPaths(parentPrefix, _prefix), // Propagate the prefix
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

  /// Joins two path segments into a single path.
  ///
  /// [base]: The base path segment.
  /// [child]: The child path segment to be appended to the base.
  ///
  /// Returns the combined path.
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

  /// Joins two names into a single hierarchical name.
  ///
  /// [parent]: The parent name.
  /// [child]: The child name to be appended to the parent.
  ///
  /// Returns the combined name.
  static String _joinNames(String? parent, String? child) {
    if (parent == null || parent.isEmpty) return child ?? '';
    if (child == null || child.isEmpty) return parent;
    return '$parent.$child';
  }
}

// extension RouterStaticFiles on Router {
//   /// Serve a single static file with the default filesystem.
//   ///
//   /// [relativePath]: The URL path to serve the file at.
//   /// [filePath]: The filesystem path to the file.
//   /// [fs]: Optional custom filesystem.
//   void staticFile(String relativePath, String filePath, [file.FileSystem? fs]) {
//     staticFileFS(
//         relativePath, filePath, Dir(p.dirname(filePath), fileSystem: fs));
//   }

//   /// Serve a single static file with a custom filesystem.
//   ///
//   /// [relativePath]: The URL path to serve the file at.
//   /// [filePath]: The filesystem path to the file.
//   /// [fs]: The custom filesystem directory.
//   void staticFileFS(String relativePath, String filePath, Dir fs) {
//     if (relativePath.contains(':') || relativePath.contains('*')) {
//       throw Exception(
//           'URL parameters cannot be used when serving a static file');
//     }

//     final fileHandler = FileHandler.fromDir(fs);
//     final fileName = p.basename(filePath);

//     handler(EngineContext context) async {
//       await fileHandler.serveFile(context.request.httpRequest, fileName);
//     }

//     get(relativePath, handler);
//     head(relativePath, handler);
//   }

//   /// Serve a directory of static files with the default filesystem.
//   ///
//   /// [relativePath]: The URL path to serve the directory at.
//   /// [rootPath]: The filesystem path to the root directory.
//   /// [fs]: Optional custom filesystem.
//   void static(String relativePath, String rootPath, [file.FileSystem? fs]) {
//     staticFS(relativePath, Dir(rootPath, fileSystem: fs));
//   }

//   /// Serve a directory of static files with a custom filesystem.
//   ///
//   /// [relativePath]: The URL path to serve the directory at.
//   /// [dir]: The custom filesystem directory.
//   void staticFS(String relativePath, Dir dir) {
//     if (relativePath.contains(':') || relativePath.contains('*')) {
//       throw Exception(
//           'URL parameters cannot be used when serving a static folder');
//     }

//     final urlPattern = p.join(relativePath, '{*filepath}');
//     final fileHandler = FileHandler.fromDir(dir);

//     handler(EngineContext context) async {
//       final requestPath = context.param('filepath') as String;
//       await fileHandler.serveFile(context.request.httpRequest, requestPath);
//     }

//     get(urlPattern, handler);
//     head(urlPattern, handler);
//   }
// }
