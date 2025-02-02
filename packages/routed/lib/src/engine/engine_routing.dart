part of 'engine.dart';

/// Extension on the [Engine] class to provide routing capabilities.
extension EngineRouting on Engine {
  /// Registers a GET route with the given [path] and [handler].
  ///
  /// [middlewares] is an optional list of middleware to apply to this route.
  /// [constraints] is an optional map of constraints to apply to this route.
  RouteBuilder get(String path, Handler handler,
      {List<Middleware> middlewares = const [],
      Map<String, dynamic> constraints = const {}}) {
    return _defaultRouter.get(path, handler,
        middlewares: middlewares, constraints: constraints);
  }

  /// Registers a POST route with the given [path] and [handler].
  ///
  /// [middlewares] is an optional list of middleware to apply to this route.
  /// [constraints] is an optional map of constraints to apply to this route.
  RouteBuilder post(String path, Handler handler,
      {List<Middleware> middlewares = const [],
      Map<String, dynamic> constraints = const {}}) {
    return _defaultRouter.post(path, handler,
        middlewares: middlewares, constraints: constraints);
  }

  /// Registers a PUT route with the given [path] and [handler].
  ///
  /// [middlewares] is an optional list of middleware to apply to this route.
  /// [constraints] is an optional map of constraints to apply to this route.
  RouteBuilder put(String path, Handler handler,
      {List<Middleware> middlewares = const [],
      Map<String, dynamic> constraints = const {}}) {
    return _defaultRouter.put(path, handler,
        middlewares: middlewares, constraints: constraints);
  }

  /// Registers a DELETE route with the given [path] and [handler].
  ///
  /// [middlewares] is an optional list of middleware to apply to this route.
  /// [constraints] is an optional map of constraints to apply to this route.
  RouteBuilder delete(String path, Handler handler,
      {List<Middleware> middlewares = const [],
      Map<String, dynamic> constraints = const {}}) {
    return _defaultRouter.delete(path, handler,
        middlewares: middlewares, constraints: constraints);
  }

  /// Registers a PATCH route with the given [path] and [handler].
  ///
  /// [middlewares] is an optional list of middleware to apply to this route.
  /// [constraints] is an optional map of constraints to apply to this route.
  RouteBuilder patch(String path, Handler handler,
      {List<Middleware> middlewares = const [],
      Map<String, dynamic> constraints = const {}}) {
    return _defaultRouter.patch(path, handler,
        middlewares: middlewares, constraints: constraints);
  }

  /// Registers a HEAD route with the given [path] and [handler].
  ///
  /// [middlewares] is an optional list of middleware to apply to this route.
  /// [constraints] is an optional map of constraints to apply to this route.
  RouteBuilder head(String path, Handler handler,
      {List<Middleware> middlewares = const [],
      Map<String, dynamic> constraints = const {}}) {
    return _defaultRouter.head(path, handler,
        middlewares: middlewares, constraints: constraints);
  }

  /// Registers an OPTIONS route with the given [path] and [handler].
  ///
  /// [middlewares] is an optional list of middleware to apply to this route.
  /// [constraints] is an optional map of constraints to apply to this route.
  RouteBuilder options(String path, Handler handler,
      {List<Middleware> middlewares = const [],
      Map<String, dynamic> constraints = const {}}) {
    return _defaultRouter.options(path, handler,
        middlewares: middlewares, constraints: constraints);
  }

  /// Registers a CONNECT route with the given [path] and [handler].
  ///
  /// [middlewares] is an optional list of middleware to apply to this route.
  RouteBuilder connect(String path, Handler handler,
      {List<Middleware> middlewares = const []}) {
    return _defaultRouter.connect(path, handler, middlewares: middlewares);
  }

  /// Registers a route with the given [method], [path], and [handler].
  ///
  /// [middlewares] is an optional list of middleware to apply to this route.
  /// [constraints] is an optional map of constraints to apply to this route.
  RouteBuilder handle(String method, String path, Handler handler,
      {List<Middleware> middlewares = const [], constraints = const {}}) {
    return _defaultRouter.handle(method, path, handler,
        middlewares: middlewares, constraints: constraints);
  }

  /// Registers a fallback route with the given [handler].
  ///
  /// This route will match any path that does not match any other registered route.
  /// [middlewares] is an optional list of middleware to apply to this route.
  RouteBuilder fallback(Handler handler,
      {List<Middleware> middlewares = const []}) {
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
  /// The [builder] function is used to define the routes within the group.
  RouterGroupBuilder group({
    String path = '',
    List<Middleware> middlewares = const [],
    void Function(Router)? builder,
  }) {
    return _defaultRouter.group(
        path: path, middlewares: middlewares, builder: builder);
  }
}
