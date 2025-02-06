part of 'engine.dart';

extension ServerExtension on Engine {
  /// Start listening for HTTP requests on the given host/port.
  ///
  /// This method initializes the HTTP server and begins handling incoming requests.
  ///
  /// Parameters:
  /// - [host]: The host address to bind to. Defaults to '127.0.0.1'.
  /// - [port]: The port number to listen on. If null, port 0 will be used.
  /// - [echoRoutes]: Whether to print the registered routes when starting. Defaults to true.
  ///
  /// Throws:
  /// - [SocketException] if the server cannot bind to the specified host/port.
  Future<void> serve(
      {String host = '127.0.0.1', int? port, bool echoRoutes = true}) async {
    // Build routes if not already done
    if (_engineRoutes.isEmpty) {
      _build();
    }
    if (echoRoutes) printRoutes();
    port ??= 0;
    _server = await HttpServer.bind(host, port, shared: true);
    print('Engine listening on http://$host:$port');

    // Handle incoming connections
    await for (HttpRequest httpRequest in _server!) {
      await handleRequest(httpRequest);
    }
  }

  /// Handles an individual HTTP request by matching it to registered routes.
  ///
  /// This method implements the routing logic in multiple passes:
  /// 1. Checks for exact route matches
  /// 2. Handles trailing slash redirects if enabled
  /// 3. Handles method not allowed responses if enabled
  /// 4. Attempts to match a fallback route
  /// 5. Returns 404 if no matches are found
  ///
  /// Parameters:
  /// - [httpRequest]: The incoming HTTP request to handle.
  Future<void> handleRequest(HttpRequest httpRequest) async {
    _ensureRoutes();
    final path = httpRequest.uri.path;
    final method = httpRequest.method;

    // First pass: check for exact route matches (excluding fallback routes)
    final routeMatches = _engineRoutes
        .map((r) => r.tryMatch(httpRequest))
        .where((match) =>
            match != null &&
            !(match.route != null &&
                match.route!.isFallback)) // Exclude fallback routes
        .toList();
    final exactMatch = routeMatches.where((m) => m!.matched).firstOrNull;

    if (exactMatch != null) {
      await _handleMatchedRoute(exactMatch.route!, httpRequest);
      return;
    }

    // Second pass: handle trailing slash redirects
    if (config.redirectTrailingSlash) {
      final alternativePath =
          path.endsWith('/') ? path.substring(0, path.length - 1) : '$path/';

      final alternativeMatch = _engineRoutes
          .where((r) => r.path == alternativePath && r.method == method)
          .firstOrNull;

      if (alternativeMatch != null) {
        _redirectRequest(httpRequest, alternativePath, method);
        return;
      }
    }

    // Third pass: handle method not allowed
    if (config.handleMethodNotAllowed) {
      final methodMismatches = routeMatches.where((m) => m!.isMethodMismatch);

      if (methodMismatches.isNotEmpty) {
        final allowedMethods = _engineRoutes
            .where((r) => r.path == path)
            .map((r) => r.method)
            .toSet();

        httpRequest.response.headers.add('Allow', allowedMethods.join(', '));
        httpRequest.response.statusCode = HttpStatus.methodNotAllowed;
        await httpRequest.response.close();
        return;
      }
    }

    // Fourth pass: check for fallback routes if no other match was found
    final fallbackRoutes = _engineRoutes.where((r) => r.isFallback).toList();
    if (fallbackRoutes.isNotEmpty) {
      // Find the most specific fallback route using fuzzy matching
      EngineRoute? mostSpecificFallback;
      int maxSimilarityScore = 0;

      for (final fallbackRoute in fallbackRoutes) {
        // Extract the static part of the fallback route's path
        final staticPath = _extractStaticPath(fallbackRoute.path);

        // Calculate the similarity score between the request path and the static path
        final similarityScore =
            fuzzy.ratio(path, staticPath.isNotEmpty ? staticPath : "/");

        // Update the most specific fallback route if the similarity score is higher
        if (similarityScore > maxSimilarityScore) {
          maxSimilarityScore = similarityScore;
          mostSpecificFallback = fallbackRoute;
        }
      }

      if (mostSpecificFallback != null) {
        await _handleMatchedRoute(mostSpecificFallback, httpRequest);
        return;
      }
    }

    // No matches found
    httpRequest.response.statusCode = HttpStatus.notFound;
    httpRequest.response.write('404 Not Found');
    await httpRequest.response.close();
  }

  /// Handles a matched route by creating a context and executing the middleware chain.
  ///
  /// Parameters:
  /// - [route]: The matched route to handle.
  /// - [httpRequest]: The original HTTP request.
  ///
  /// This method creates an [EngineContext] and executes all middleware and the route handler
  /// in the correct order. It also handles any errors that occur during processing.
  Future<void> _handleMatchedRoute(
      EngineRoute route, HttpRequest httpRequest) async {
    final request = Request(httpRequest, {});
    final response = Response(httpRequest.response);

    final context = EngineContext(
      request: request,
      response: response,
      route: route,
      engine: this,
      handlers: [...middlewares, ...route.middlewares, route.handler],
    );

    try {
      await context.run();
    } catch (err, stack) {
      // Anything that wasn't caught at a lower level gets caught here.
      _handleGlobalError(context, err, stack);
    } finally {
      // Only close if not already closed
      if (!response.isClosed) {
        response.close();
      }
    }
  }

  /// Handles any uncaught errors that occur during request processing.
  ///
  /// Parameters:
  /// - [ctx]: The current engine context.
  /// - [err]: The error that was caught.
  /// - [stack]: The stack trace associated with the error.
  ///
  /// This method provides different error handling based on the type of error:
  /// - [ValidationError]: Returns a 422 with validation errors
  /// - [EngineError]: Returns the specified error code and message
  /// - Other errors: Returns a 500 Internal Server Error
  void _handleGlobalError(
    EngineContext ctx,
    Object err,
    StackTrace stack,
  ) {
    // For logging—replace with your logging approach (e.g. Sentry, package:logging, etc).
    stderr.writeln('Global error caught in Engine: $err\n$stack');

    if (err is ValidationError) {
      ctx.json(err.errors,
          statusCode: err.code ?? HttpStatus.unprocessableEntity);
      ctx.abort();
      return;
    }
    if (err is EngineError && err.code != null) {
      // Known engine-related error with a custom status code.

      // You can return JSON, HTML, plain text, etc. For example:
      ctx.string('EngineError(${err.code}): ${err.message}',
          statusCode: err.code!);
    } else {
      // Fallback to internal server error for unknown/unhandled
      // Customize the body for dev, staging, or production:
      ctx.string('An unexpected error occurred. Please try again later.',
          statusCode: HttpStatus.internalServerError);
    }

    // Make sure no further processing occurs.
    ctx.abort();
  }

  /// Performs a redirect by setting the appropriate status code and Location header.
  ///
  /// Parameters:
  /// - [request]: The HTTP request to redirect.
  /// - [newPath]: The path to redirect to.
  /// - [method]: The HTTP method of the original request.
  ///
  /// Uses 301 for GET requests and 307 for all other methods.
  void _redirectRequest(HttpRequest request, String newPath, String method) {
    final statusCode = method == 'GET'
        ? HttpStatus.movedPermanently // 301
        : HttpStatus.temporaryRedirect; // 307

    request.response.statusCode = statusCode;
    request.response.headers.add('Location', newPath);
  }

  /// Stops the HTTP server and releases all resources.
  ///
  /// This method should be called when shutting down the application to ensure
  /// proper cleanup of server resources.
  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }
}

/// Extracts the static part of a fallback route's path by removing the `{__fallback:*}` parameter.
String _extractStaticPath(String path) {
  return path.replaceAll('/{__fallback:*}', '');
}
