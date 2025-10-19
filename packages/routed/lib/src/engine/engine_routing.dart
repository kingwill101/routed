part of 'engine.dart';

/// Extension providing routing methods for the [Engine] class.
///
/// This extension adds convenience methods for registering routes with different
/// HTTP methods directly on the engine instance. These methods delegate to the
/// default router internally.
///
/// Example:
/// ```dart
/// final engine = Engine();
/// engine.get('/users', (req) => Response.ok('List users'));
/// engine.post('/users', (req) => Response.ok('Create user'));
/// ```
extension EngineRouting on Engine {
  /// Registers a GET route with the given [path] and [handler].
  ///
  /// GET requests are typically used for retrieving resources without side effects.
  ///
  /// Example:
  /// ```dart
  /// engine.get('/users/:id', (req) {
  ///   final id = req.params['id'];
  ///   return Response.ok('User $id');
  /// });
  /// ```
  ///
  /// The [middlewares] parameter allows specifying middleware to apply to this route.
  /// The [constraints] parameter allows adding custom validation rules.
  RouteBuilder get(
    String path,
    RouteHandler handler, {
    List<Middleware> middlewares = const [],
    Map<String, dynamic> constraints = const {},
  }) {
    return _defaultRouter.get(
      path,
      handler,
      middlewares: middlewares,
      constraints: constraints,
    );
  }

  /// Registers a POST route with the given [path] and [handler].
  ///
  /// POST requests are typically used for creating new resources or submitting
  /// forms with side effects.
  ///
  /// Example:
  /// ```dart
  /// engine.post('/users', (req) async {
  ///   final data = await req.json();
  ///   return Response.ok('Created user');
  /// });
  /// ```
  ///
  /// The [middlewares] parameter allows specifying middleware to apply to this route.
  /// The [constraints] parameter allows adding custom validation rules.
  RouteBuilder post(
    String path,
    RouteHandler handler, {
    List<Middleware> middlewares = const [],
    Map<String, dynamic> constraints = const {},
  }) {
    return _defaultRouter.post(
      path,
      handler,
      middlewares: middlewares,
      constraints: constraints,
    );
  }

  /// Registers a PUT route with the given [path] and [handler].
  ///
  /// PUT requests are typically used for updating or replacing existing resources.
  ///
  /// Example:
  /// ```dart
  /// engine.put('/users/:id', (req) async {
  ///   final id = req.params['id'];
  ///   final data = await req.json();
  ///   return Response.ok('Updated user $id');
  /// });
  /// ```
  ///
  /// The [middlewares] parameter allows specifying middleware to apply to this route.
  /// The [constraints] parameter allows adding custom validation rules.
  RouteBuilder put(
    String path,
    RouteHandler handler, {
    List<Middleware> middlewares = const [],
    Map<String, dynamic> constraints = const {},
  }) {
    return _defaultRouter.put(
      path,
      handler,
      middlewares: middlewares,
      constraints: constraints,
    );
  }

  /// Registers a DELETE route with the given [path] and [handler].
  ///
  /// DELETE requests are typically used for removing resources.
  ///
  /// Example:
  /// ```dart
  /// engine.delete('/users/:id', (req) {
  ///   final id = req.params['id'];
  ///   return Response.ok('Deleted user $id');
  /// });
  /// ```
  ///
  /// The [middlewares] parameter allows specifying middleware to apply to this route.
  /// The [constraints] parameter allows adding custom validation rules.
  RouteBuilder delete(
    String path,
    RouteHandler handler, {
    List<Middleware> middlewares = const [],
    Map<String, dynamic> constraints = const {},
  }) {
    return _defaultRouter.delete(
      path,
      handler,
      middlewares: middlewares,
      constraints: constraints,
    );
  }

  /// Registers a PATCH route with the given [path] and [handler].
  ///
  /// PATCH requests are typically used for partial updates to existing resources.
  ///
  /// Example:
  /// ```dart
  /// engine.patch('/users/:id', (req) async {
  ///   final id = req.params['id'];
  ///   final updates = await req.json();
  ///   return Response.ok('Patched user $id');
  /// });
  /// ```
  ///
  /// The [middlewares] parameter allows specifying middleware to apply to this route.
  /// The [constraints] parameter allows adding custom validation rules.
  RouteBuilder patch(
    String path,
    RouteHandler handler, {
    List<Middleware> middlewares = const [],
    Map<String, dynamic> constraints = const {},
  }) {
    return _defaultRouter.patch(
      path,
      handler,
      middlewares: middlewares,
      constraints: constraints,
    );
  }

  /// Registers a HEAD route with the given [path] and [handler].
  ///
  /// HEAD requests are identical to GET requests but return only headers without
  /// a response body. Useful for checking resource existence or metadata.
  ///
  /// Example:
  /// ```dart
  /// engine.head('/users/:id', (req) {
  ///   return Response.ok('', headers: {'X-User-Exists': 'true'});
  /// });
  /// ```
  ///
  /// The [middlewares] parameter allows specifying middleware to apply to this route.
  /// The [constraints] parameter allows adding custom validation rules.
  RouteBuilder head(
    String path,
    RouteHandler handler, {
    List<Middleware> middlewares = const [],
    Map<String, dynamic> constraints = const {},
  }) {
    return _defaultRouter.head(
      path,
      handler,
      middlewares: middlewares,
      constraints: constraints,
    );
  }

  /// Registers an OPTIONS route with the given [path] and [handler].
  ///
  /// OPTIONS requests are used to describe communication options for the target
  /// resource, typically for CORS preflight requests.
  ///
  /// Example:
  /// ```dart
  /// engine.options('/api/*', (req) {
  ///   return Response.ok('', headers: {
  ///     'Allow': 'GET, POST, OPTIONS',
  ///   });
  /// });
  /// ```
  ///
  /// The [middlewares] parameter allows specifying middleware to apply to this route.
  /// The [constraints] parameter allows adding custom validation rules.
  RouteBuilder options(
    String path,
    RouteHandler handler, {
    List<Middleware> middlewares = const [],
    Map<String, dynamic> constraints = const {},
  }) {
    return _defaultRouter.options(
      path,
      handler,
      middlewares: middlewares,
      constraints: constraints,
    );
  }

  /// Registers a CONNECT route with the given [path] and [handler].
  ///
  /// CONNECT requests are used to establish a tunnel to the server, typically
  /// for HTTPS connections through HTTP proxies.
  ///
  /// The [middlewares] parameter allows specifying middleware to apply to this route.
  RouteBuilder connect(
    String path,
    RouteHandler handler, {
    List<Middleware> middlewares = const [],
  }) {
    return _defaultRouter.connect(path, handler, middlewares: middlewares);
  }

  /// Registers a route with a custom HTTP [method], [path], and [handler].
  ///
  /// This method allows registering routes for any HTTP method, including
  /// non-standard methods.
  ///
  /// Example:
  /// ```dart
  /// engine.handle('PURGE', '/cache/:key', (req) {
  ///   final key = req.params['key'];
  ///   return Response.ok('Purged cache key $key');
  /// });
  /// ```
  ///
  /// The [middlewares] parameter allows specifying middleware to apply to this route.
  /// The [constraints] parameter allows adding custom validation rules.
  RouteBuilder handle(
    String method,
    String path,
    RouteHandler handler, {
    List<Middleware> middlewares = const [],
    Map<String, dynamic> constraints = const {},
  }) {
    return _defaultRouter.handle(
      method,
      path,
      handler,
      middlewares: middlewares,
      constraints: constraints,
    );
  }

  /// Registers a fallback route with the given [handler].
  ///
  /// Fallback routes are executed when no other route matches the request.
  /// This is useful for implementing custom 404 pages or catch-all handlers.
  ///
  /// Multiple fallback routes are allowed (for example, a global fallback and
  /// group-specific fallbacks). When no regular route matches, the engine
  /// selects the most specific fallback by comparing how closely each fallback's
  /// static prefix matches the request path.
  ///
  /// Example:
  /// ```dart
  /// engine.fallback((req) {
  ///   return Response.notFound('Page not found: ${req.uri.path}');
  /// });
  /// ```
  ///
  /// The [middlewares] parameter allows specifying middleware to apply to this fallback.
  RouteBuilder fallback(
    RouteHandler handler, {
    List<Middleware> middlewares = const [],
  }) {
    // We use a wildcard parameter in the path that will match anything.
    // We also add a flag in constraints so later when building the EngineRoute
    // we know this route is the fallback.
    return _defaultRouter.handle(
      'GET',
      '/{__fallback:*}', // a path that matches everything
      handler,
      middlewares: middlewares,
      constraints: {'isFallback': true},
    );
  }

  /// Creates a group of routes with a common [path] prefix and [middlewares].
  ///
  /// Route groups allow organizing related routes together and applying shared
  /// middleware or path prefixes without repetition.
  ///
  /// Example:
  /// ```dart
  /// engine.group(
  ///   path: '/api/v1',
  ///   middlewares: [AuthMiddleware()],
  ///   builder: (router) {
  ///     router.get('/users', listUsers);
  ///     router.post('/users', createUser);
  ///   },
  /// );
  /// ```
  ///
  /// The [builder] function receives a router instance for defining routes
  /// within the group. All routes in the group inherit the prefix and middleware.
  RouterGroupBuilder group({
    String path = '',
    List<Middleware> middlewares = const [],
    void Function(Router)? builder,
  }) {
    return _defaultRouter.group(
      path: path,
      middlewares: middlewares,
      builder: builder,
    );
  }
}
