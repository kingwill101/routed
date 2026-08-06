import 'package:routed/routed.dart';
import 'package:routed/src/router/registered_route.dart';
import 'package:routed/src/router/router_group_builder.dart';
import 'package:routed/src/static_files.dart';
export 'route_builder.dart';

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

  /// WebSocket routes defined at this level
  final List<RouterWebSocketRoute> _wsRoutes = [];

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
  /// [path]: appended to this router's path
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
  RouteBuilder fallback(
    Handler handler, {
    List<Middleware> middlewares = const [],
  }) {
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

  /// Registers a WebSocket route with the router.
  void ws(
    String path,
    WebSocketHandler handler, {
    List<Middleware> middlewares = const [],
  }) {
    _wsRoutes.add(
      RouterWebSocketRoute(
        path: path,
        handler: handler,
        routeMiddlewares: middlewares,
      ),
    );
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
  /// [schema]: Optional API schema metadata for this route.
  RouteBuilder get(
    String path,
    RouteHandler handler, {
    List<Middleware> middlewares = const [],
    Map<String, dynamic> constraints = const {},
    RouteSchema? schema,
  }) {
    return handle(
      "GET",
      path,
      handler,
      middlewares: middlewares,
      constraints: constraints,
      schema: schema,
    );
  }

  /// Registers a POST route with the router.
  ///
  /// [path]: The path for the POST route.
  /// [handler]: The handler function for the POST route.
  /// [middlewares]: Optional middlewares specific to this route.
  /// [constraints]: Optional constraints for the route parameters.
  /// [schema]: Optional API schema metadata for this route.
  RouteBuilder post(
    String path,
    RouteHandler handler, {
    List<Middleware> middlewares = const [],
    Map<String, dynamic> constraints = const {},
    RouteSchema? schema,
  }) {
    return handle(
      "POST",
      path,
      handler,
      middlewares: middlewares,
      constraints: constraints,
      schema: schema,
    );
  }

  /// Registers a PUT route with the router.
  ///
  /// [path]: The path for the PUT route.
  /// [handler]: The handler function for the PUT route.
  /// [middlewares]: Optional middlewares specific to this route.
  /// [constraints]: Optional constraints for the route parameters.
  /// [schema]: Optional API schema metadata for this route.
  RouteBuilder put(
    String path,
    RouteHandler handler, {
    List<Middleware> middlewares = const [],
    Map<String, dynamic> constraints = const {},
    RouteSchema? schema,
  }) {
    return handle(
      "PUT",
      path,
      handler,
      middlewares: middlewares,
      constraints: constraints,
      schema: schema,
    );
  }

  /// Registers a DELETE route with the router.
  ///
  /// [path]: The path for the DELETE route.
  /// [handler]: The handler function for the DELETE route.
  /// [middlewares]: Optional middlewares specific to this route.
  /// [constraints]: Optional constraints for the route parameters.
  /// [schema]: Optional API schema metadata for this route.
  RouteBuilder delete(
    String path,
    RouteHandler handler, {
    List<Middleware> middlewares = const [],
    Map<String, dynamic> constraints = const {},
    RouteSchema? schema,
  }) {
    return handle(
      "DELETE",
      path,
      handler,
      middlewares: middlewares,
      constraints: constraints,
      schema: schema,
    );
  }

  /// Registers a PATCH route with the router.
  ///
  /// [path]: The path for the PATCH route.
  /// [handler]: The handler function for the PATCH route.
  /// [middlewares]: Optional middlewares specific to this route.
  /// [constraints]: Optional constraints for the route parameters.
  /// [schema]: Optional API schema metadata for this route.
  RouteBuilder patch(
    String path,
    RouteHandler handler, {
    List<Middleware> middlewares = const [],
    Map<String, dynamic> constraints = const {},
    RouteSchema? schema,
  }) {
    return handle(
      "PATCH",
      path,
      handler,
      middlewares: middlewares,
      constraints: constraints,
      schema: schema,
    );
  }

  /// Registers a HEAD route with the router.
  ///
  /// [path]: The path for the HEAD route.
  /// [handler]: The handler function for the HEAD route.
  /// [middlewares]: Optional middlewares specific to this route.
  /// [constraints]: Optional constraints for the route parameters.
  /// [schema]: Optional API schema metadata for this route.
  RouteBuilder head(
    String path,
    RouteHandler handler, {
    List<Middleware> middlewares = const [],
    Map<String, dynamic> constraints = const {},
    RouteSchema? schema,
  }) {
    return handle(
      "HEAD",
      path,
      handler,
      middlewares: middlewares,
      constraints: constraints,
      schema: schema,
    );
  }

  /// Registers an OPTIONS route with the router.
  ///
  /// [path]: The path for the OPTIONS route.
  /// [handler]: The handler function for the OPTIONS route.
  /// [middlewares]: Optional middlewares specific to this route.
  /// [constraints]: Optional constraints for the route parameters.
  /// [schema]: Optional API schema metadata for this route.
  RouteBuilder options(
    String path,
    RouteHandler handler, {
    List<Middleware> middlewares = const [],
    Map<String, dynamic> constraints = const {},
    RouteSchema? schema,
  }) {
    return handle(
      "OPTIONS",
      path,
      handler,
      middlewares: middlewares,
      constraints: constraints,
      schema: schema,
    );
  }

  /// Registers a CONNECT route with the router.
  ///
  /// [path]: The path for the CONNECT route.
  /// [handler]: The handler function for the CONNECT route.
  /// [middlewares]: Optional middlewares specific to this route.
  /// [constraints]: Optional constraints for the route parameters.
  /// [schema]: Optional API schema metadata for this route.
  RouteBuilder connect(
    String path,
    RouteHandler handler, {
    List<Middleware> middlewares = const [],
    Map<String, dynamic> constraints = const {},
    RouteSchema? schema,
  }) {
    return handle(
      "CONNECT",
      path,
      handler,
      middlewares: middlewares,
      constraints: constraints,
      schema: schema,
    );
  }

  /// Registers a route that accepts any HTTP method.
  ///
  /// [path]: The path for the route.
  /// [handler]: The handler function for the route.
  /// [middlewares]: Optional middlewares specific to this route.
  /// [constraints]: Optional constraints for the route parameters.
  /// [schema]: Optional API schema metadata for this route.
  RouteBuilder any(
    String path,
    Handler handler, {
    List<Middleware> middlewares = const [],
    Map<String, dynamic> constraints = const {},
    RouteSchema? schema,
  }) {
    // Create routes for all common HTTP methods
    final methods = [
      'GET',
      'POST',
      'PUT',
      'DELETE',
      'PATCH',
      'HEAD',
      'OPTIONS',
    ];

    // Use the first route for naming and return its builder
    RouteBuilder? firstBuilder;

    for (final method in methods) {
      final builder = handle(
        method,
        path,
        handler,
        middlewares: middlewares,
        constraints: constraints,
        schema: schema,
      );

      firstBuilder ??= builder;
    }

    return firstBuilder!;
  }

  /// Internal helper to create and store a [RegisteredRoute].
  ///
  /// [method]: The HTTP method for the route (e.g., GET, POST).
  /// [path]: The path for the route.
  /// [handler]: The handler function for the route.
  /// [middlewares]: Optional middlewares specific to this route.
  /// [constraints]: Optional constraints for the route parameters.
  /// [schema]: Optional API schema metadata for this route.
  RouteBuilder handle(
    String method,
    String path,
    RouteHandler handler, {
    List<Middleware> middlewares = const [],
    Map<String, dynamic> constraints = const {},
    RouteSchema? schema,
  }) {
    final source = _captureRouteRegistrationSource();
    final fullPath = _joinPaths(_prefix, path);
    final route = RegisteredRoute(
      method: method,
      path: fullPath,
      handler: handler,
      routeMiddlewares: middlewares,
      constraints: constraints,
      schema: schema,
      sourceFile: source.file,
      sourceLine: source.line,
      sourceColumn: source.column,
    );
    _routes.add(route);
    return RouteBuilder(route, this);
  }

  //
  // /// Register a class-based view with the router.
  // ///
  // /// [path]: The path for the view.
  // /// [view]: The view instance to register.
  // /// [middlewares]: Optional middlewares specific to this view.
  // /// [constraints]: Optional constraints for the route parameters.
  // RouteBuilder view(
  //   String path,
  //   View view, {
  //   List<Middleware> middlewares = const [],
  //   Map<String, dynamic> constraints = const {},
  // }) {
  //   // Convert the view to a handler function
  //   handler(EngineContext context) => view.dispatch(context);
  //
  //   // For views, we'll register routes for all methods the view allows
  //   final allowedMethods = view.allowedMethods;
  //
  //   // Use the first route for naming and return its builder
  //   RouteBuilder? firstBuilder;
  //
  //   for (final method in allowedMethods) {
  //     final builder = handle(method, path, handler,
  //         middlewares: middlewares, constraints: constraints);
  //
  //     firstBuilder ??= builder;
  //   }
  //
  //   return firstBuilder ?? // Fallback in case allowedMethods is empty (shouldn't happen)
  //       handle('GET', path, handler,
  //           middlewares: middlewares, constraints: constraints);
  // }

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

    for (final wsRoute in _wsRoutes) {
      wsRoute.finalMiddlewares = [...combinedMW, ...wsRoute.routeMiddlewares];
      if (!wsRoute.path.startsWith(_prefix)) {
        wsRoute.path = _joinPaths(_prefix, wsRoute.path);
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

  List<RouterWebSocketRoute> getAllWebSocketRoutes() {
    final results = <RouterWebSocketRoute>[];
    results.addAll(_wsRoutes);
    for (final child in _children) {
      results.addAll(child.getAllWebSocketRoutes());
    }
    return results;
  }

  /// Resolves [MiddlewareReference] placeholders into executable middleware.
  void resolveMiddlewareReferences(
    MiddlewareRegistry registry,
    Container container,
  ) {
    registry.resolveInPlace(groupMiddlewares, container);

    for (final route in _routes) {
      route.finalMiddlewares = registry.resolveAll(
        route.finalMiddlewares,
        container,
      );
    }

    for (final wsRoute in _wsRoutes) {
      wsRoute.finalMiddlewares = registry.resolveAll(
        wsRoute.finalMiddlewares,
        container,
      );
    }

    for (final child in _children) {
      child.resolveMiddlewareReferences(registry, container);
    }
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

  static ({String? file, int? line, int? column})
  _captureRouteRegistrationSource() {
    final frames = StackTrace.current.toString().split('\n');
    final framePattern = RegExp(r'([^\s()]+\.dart):(\d+):(\d+)');

    for (final frame in frames) {
      if (frame.contains('package:routed/')) continue;
      if (frame.contains('(dart:')) continue;

      final match = framePattern.firstMatch(frame);
      if (match == null) continue;

      final file = match.group(1);
      final line = int.tryParse(match.group(2) ?? '');
      final column = int.tryParse(match.group(3) ?? '');
      if (file == null || line == null || column == null) continue;
      return (file: file, line: line, column: column);
    }

    return (file: null, line: null, column: null);
  }
}

class RouterWebSocketRoute {
  RouterWebSocketRoute({
    required this.path,
    required this.handler,
    List<Middleware> routeMiddlewares = const [],
  }) : routeMiddlewares = List<Middleware>.from(routeMiddlewares);

  String path;
  final WebSocketHandler handler;
  final List<Middleware> routeMiddlewares;
  List<Middleware> finalMiddlewares = [];
}
