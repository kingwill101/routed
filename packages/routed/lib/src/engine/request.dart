part of 'engine.dart';

/// Extension methods for handling HTTP server functionality.
extension ServerExtension on Engine {
  /// Start listening for HTTP requests on the given host/port.
  ///
  /// This method initializes the HTTP server and begins handling incoming requests.
  ///
  /// Parameters:
  /// - [host]: The host address to bind to. Defaults to '127.0.0.1'.
  /// - [port]: The port number to listen on. If null, port 0 will be used.
  /// - [echo]: Whether to print the registered routes when starting. Defaults to true.
  ///
  /// Throws:
  /// - [SocketException] if the server cannot bind to the specified host/port.
  Future<void> serve({
    String host = '127.0.0.1',
    int? port,
    bool echo = true,
  }) async {
    // Build routes if not already done
    if (_engineRoutes.isEmpty) {
      _build();
    }
    // Ensure proxy configuration is parsed
    if (config.features.enableProxySupport) {
      await config.ensureTrustedProxiesParsed();
    }
    if (echo) printRoutes();

    runZonedGuarded(
      () async {
        _server = await HttpServer.bind(host, port ?? 0, shared: true);
        final boundPort = _server!.port;

        await LoggingContext.withValues({
          'event': 'engine_started',
          'scheme': 'http',
          'host': host,
          'port': boundPort,
        }, (logger) => logger.info('Engine listening'));

        if (echo) {
          print('Engine listening on http://$host:$boundPort');
        }

        _setupShutdownController();

        // Handle incoming connections
        await for (HttpRequest httpRequest in _server!) {
          // Handle each request concurrently
          // ignore: unawaited_futures
          handleRequest(httpRequest).catchError((e, s) async {
            // Best-effort error handling if nothing else catches it
            try {
              httpRequest.response.statusCode = HttpStatus.internalServerError;
              await httpRequest.response.close();
            } catch (_) {}
          });
        }
      },
      (error, stack) {
        LoggingContext.withValues({
          'event': 'engine_start_error',
          'error_type': error.runtimeType.toString(),
          'stack_trace': stack.toString(),
        }, (logger) => logger.error('Engine failed to start: $error'));
        stderr.writeln('Engine failed to start: $error');
      },
    );
  }

  bool _isWebSocket(HttpRequest httpRequest) {
    return WebSocketTransformer.isUpgradeRequest(httpRequest);
  }

  Future<bool> handleWs(HttpRequest httpRequest) async {
    if (!WebSocketTransformer.isUpgradeRequest(httpRequest)) {
      return false;
    }
    final requestPath = httpRequest.uri.path;
    WebSocketEngineRoute? route;
    Map<String, dynamic> pathParams = const {};
    for (final candidate in _wsRoutes.values) {
      if (!candidate.pattern.hasMatch(requestPath) &&
          !candidate.pattern.hasMatch(
            requestPath.endsWith('/') ? requestPath : '$requestPath/',
          )) {
        continue;
      }
      route = candidate;
      pathParams = candidate.extractParameters(requestPath);
      break;
    }

    if (route == null) {
      return false;
    }

    final container = createRequestContainer(httpRequest, httpRequest.response);
    try {
      await _handleWebSocketRoute(
        route,
        httpRequest,
        container,
        pathParameters: pathParams,
      );
    } finally {
      await cleanupRequestContainer(container);
    }
    return true;
  }

  /// Internal method to handle an individual HTTP request.
  ///
  /// This method implements the routing logic in multiple passes:
  /// 1. Checks for WebSocket upgrade requests
  /// 2. Checks for exact route matches
  /// 3. Handles trailing slash redirects if enabled
  /// 4. Handles method not allowed responses if enabled
  /// 5. Attempts to match a fallback route
  /// 6. Returns 404 if no matches are found
  ///
  /// Parameters:
  /// - [httpRequest]: The incoming HTTP request to handle.
  Future<Request?> _handleRequest(
    HttpRequest httpRequest,
    Container container,
  ) async {
    _ensureRoutes();

    if (_isWebSocket(httpRequest)) {
      if (await handleWs(httpRequest)) return null;
    }
    final path = httpRequest.uri.path;
    final method = httpRequest.method;

    if (config.features.enableProxySupport) {
      await config.ensureTrustedProxiesParsed();
    }

    final configMap = container.get<Config>();
    final maxRequestSizeSetting = configMap.get<Object?>(
      'security.max_request_size',
    );
    final maxRequestSize = maxRequestSizeSetting is int
        ? maxRequestSizeSetting
        : config.security.maxRequestSize;

    final HttpRequest effectiveRequest = maxRequestSize > 0
        ? WrappedRequest(httpRequest, maxRequestSize)
        : httpRequest;

    final normalizedPath = path.isEmpty ? '/' : path;
    final candidateRoutes = _engineRoutes
        .where((route) {
          return !route.isFallback && route.method == method;
        })
        .toList(growable: false);

    bool matchesCurrentPath = false;
    for (final candidate in candidateRoutes) {
      final pattern = candidate._uriPattern;
      if (pattern.hasMatch(normalizedPath) ||
          pattern.hasMatch(
            normalizedPath.endsWith('/') ? normalizedPath : '$normalizedPath/',
          )) {
        matchesCurrentPath = true;
        break;
      }
    }

    // Handle trailing slash redirects only when the current path does not match.
    if (config.redirectTrailingSlash && !matchesCurrentPath) {
      final hasTrailingSlash = normalizedPath.endsWith('/');
      var alternativePath = hasTrailingSlash
          ? normalizedPath.substring(0, normalizedPath.length - 1)
          : '$normalizedPath/';

      if (alternativePath.isEmpty) {
        alternativePath = '/';
      }

      EngineRoute? alternativeMatch;
      if (alternativePath != normalizedPath) {
        alternativeMatch = candidateRoutes.firstWhereOrNull((candidate) {
          final pattern = candidate._uriPattern;
          return pattern.hasMatch(alternativePath) ||
              pattern.hasMatch(
                alternativePath.endsWith('/')
                    ? alternativePath
                    : '$alternativePath/',
              );
        });
      }

      if (alternativeMatch != null) {
        final manager = container.has<EventManager>()
            ? await container.make<EventManager>()
            : null;
        if (manager != null) {
          final nfRequest = Request(effectiveRequest, {}, config);
          final nfResponse = Response(effectiveRequest.response);
          manager.publish(
            RouteNotFoundEvent(
              EngineContext(
                request: nfRequest,
                response: nfResponse,
                engine: this,
                container: container,
              ),
            ),
          );
        }
        _redirectRequest(effectiveRequest, alternativePath, method);
        await effectiveRequest.response.close();
        return null;
      }
    }

    // Rest of existing route matching logic...
    final routeMatches = _engineRoutes
        .map((r) => r.tryMatch(effectiveRequest))
        .where(
          (match) =>
              match != null &&
              !(match.route != null && match.route!.isFallback),
        )
        .toList();

    final exactMatch = routeMatches.where((m) => m!.matched).firstOrNull;

    if (exactMatch != null) {
      try {
        return await _handleMatchedRoute(
          exactMatch.route!,
          effectiveRequest,
          container,
        );
      } on HttpException catch (e) {
        if (e.message == 'Request body exceeds the maximum allowed size.') {
          effectiveRequest.response.statusCode =
              HttpStatus.requestEntityTooLarge;
          effectiveRequest.response.write(
            'Request body exceeds the maximum allowed size.',
          );
          await effectiveRequest.response.close();
          return null;
        }
        rethrow;
      }
    }
    // Automatic OPTIONS handling when enabled and no explicit handler was found.
    if (method == 'OPTIONS' && config.defaultOptionsEnabled) {
      final allowed = _resolveAllowedMethods(path, effectiveRequest);
      if (allowed.isNotEmpty) {
        allowed.add('OPTIONS');
        if (middlewares.isNotEmpty) {
          await _runGlobalMiddlewares(
            effectiveRequest,
            container,
            onComplete: (ctx) async {
              _writeOptionsResponse(ctx.response, allowed);
              return ctx.response;
            },
          );
        } else {
          _writeOptionsResponse(effectiveRequest.response, allowed);
          await effectiveRequest.response.close();
        }
        return null;
      }
    }

    // Third pass: handle method not allowed
    if (config.handleMethodNotAllowed) {
      final methodMismatches = routeMatches.where((m) => m!.isMethodMismatch);

      if (methodMismatches.isNotEmpty) {
        final allowedMethods = _resolveAllowedMethods(path, effectiveRequest);
        allowedMethods.add('OPTIONS');

        if (method == 'OPTIONS' && middlewares.isNotEmpty) {
          await _runGlobalMiddlewares(
            effectiveRequest,
            container,
            onComplete: (ctx) async {
              _writeMethodNotAllowedResponse(ctx.response, allowedMethods);
              return ctx.response;
            },
          );
          return null;
        }

        _writeMethodNotAllowedResponse(
          effectiveRequest.response,
          allowedMethods,
        );
        await effectiveRequest.response.close();
        return null;
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
        final similarityScore = fuzzy.ratio(
          path,
          staticPath.isNotEmpty ? staticPath : "/",
        );

        // Update the most specific fallback route if the similarity score is higher
        if (similarityScore > maxSimilarityScore) {
          maxSimilarityScore = similarityScore;
          mostSpecificFallback = fallbackRoute;
        }
      }

      if (mostSpecificFallback != null) {
        return await _handleMatchedRoute(
          mostSpecificFallback,
          effectiveRequest,
          container,
        );
      }
    }

    // No matches found
    return await _respondWithNotFound(effectiveRequest, container);
  }

  Future<Request> _respondWithNotFound(
    HttpRequest httpRequest,
    Container container,
  ) async {
    final request = Request(httpRequest, {}, config);
    final response = Response(httpRequest.response);

    _onRequestStarted(request);

    final resolvedGlobal = _resolveMiddlewares(middlewares, container);
    final handlers = <Middleware>[
      for (final middleware in resolvedGlobal)
        (EngineContext ctx, Next next) => middleware(ctx, next),
    ];
    handlers.add((EngineContext ctx, Next next) async {
      if (!ctx.response.isClosed) {
        ctx.response.statusCode = HttpStatus.notFound;
        ctx.response.write('404 Not Found');
      }
      return ctx.response;
    });

    final context = EngineContext(
      request: request,
      response: response,
      handlers: handlers,
      engine: this,
      container: container,
    );

    container
      ..instance<Request>(request)
      ..instance<Response>(response)
      ..instance<EngineContext>(context);

    context
      ..set('routed.route_type', 'http')
      ..set('routed.route_name', 'routed.404')
      ..set('routed.route_path', httpRequest.uri.path);

    final manager = container.has<EventManager>()
        ? await container.make<EventManager>()
        : null;

    manager?.publish(BeforeRoutingEvent(context));
    manager?.publish(RequestStartedEvent(context));
    manager?.publish(RouteNotFoundEvent(context));

    try {
      await AppZone.run(
        body: () async {
          await LoggingContext.run(this, context, (logger) async {
            try {
              await context.run();
            } catch (err, stack) {
              manager?.publish(RoutingErrorEvent(context, null, err, stack));
              await _handleGlobalError(context, err, stack);
            } finally {
              if (!response.isClosed) {
                response.close();
              }
            }
          });
        },
        engine: this,
        context: context,
      );
    } finally {
      manager?.publish(AfterRoutingEvent(context));
      _onRequestFinished(request.id);
      manager?.publish(RequestFinishedEvent(context));
    }

    return request;
  }

  /// Handles a matched route by creating a context and executing the middleware chain.
  ///
  /// Parameters:
  /// - [route]: The matched route to handle.
  /// - [httpRequest]: The original HTTP request.
  ///
  /// This method creates an [EngineContext] and executes all middleware and the route handler
  /// in the correct order. It also handles any errors that occur during processing.
  Future<Request> _handleMatchedRoute(
    EngineRoute route,
    HttpRequest httpRequest,
    Container container,
  ) async {
    final request = Request(httpRequest, {}, config);
    final response = Response(httpRequest.response);

    _onRequestStarted(request);

    final resolvedGlobal = _resolveMiddlewares(middlewares, container);
    final resolvedRoute = _resolveMiddlewares(route.middlewares, container);

    final List<Middleware> chain = [
      for (final middleware in resolvedGlobal)
        (EngineContext ctx, Next next) => middleware(ctx, next),
      for (final middleware in resolvedRoute)
        (EngineContext ctx, Next next) => middleware(ctx, next),
    ];
    chain.add((EngineContext c, Next n) async {
      final r = await route.handler(c);
      return r;
    });

    final context = EngineContext(
      request: request,
      response: response,
      route: route,
      engine: this,
      handlers: chain,
      container: container,
    );

    container
      ..instance<Request>(request)
      ..instance<Response>(response)
      ..instance<EngineContext>(context);

    context.set('routed.route_type', 'http');
    context.set('routed.route_name', route.name ?? route.path);
    context.set('routed.route_path', route.path);

    final manager = container.has<EventManager>()
        ? await container.make<EventManager>()
        : null;

    manager?.publish(BeforeRoutingEvent(context));
    manager?.publish(RequestStartedEvent(context));

    try {
      await AppZone.run(
        body: () async {
          await LoggingContext.run(this, context, (logger) async {
            try {
              manager?.publish(RouteMatchedEvent(context, route));
              await context.run();
            } catch (err, stack) {
              manager?.publish(RoutingErrorEvent(context, route, err, stack));
              await _handleGlobalError(context, err, stack);
            } finally {
              // Close if our wrapper not yet closed; underlying may already be
              // closed by direct HttpResponse usage (e.g. static file handler).
              if (!response.isClosed) {
                response.close();
              }
            }
          });
        },
        engine: this,
        context: context,
      );
    } catch (err, stack) {
      // Anything that wasn't caught at a lower level gets caught here.
      await _handleGlobalError(context, err, stack);
    } finally {
      // Only close if not already closed
      if (!response.isClosed) {
        // response.close();
      }
      manager?.publish(AfterRoutingEvent(context, route: route));
      _onRequestFinished(request.id);
      manager?.publish(RequestFinishedEvent(context));
    }

    return request;
  }

  Future<Request> _handleWebSocketRoute(
    WebSocketEngineRoute route,
    HttpRequest httpRequest,
    Container container, {
    Map<String, dynamic> pathParameters = const <String, dynamic>{},
  }) async {
    final request = Request(
      httpRequest,
      Map<String, dynamic>.from(pathParameters),
      config,
    );
    final response = Response(httpRequest.response);
    _onRequestStarted(request);

    final resolvedGlobal = _resolveMiddlewares(middlewares, container);
    final resolvedRoute = _resolveMiddlewares(route.middlewares, container);

    final List<Middleware> chain = [
      for (final middleware in resolvedGlobal)
        (EngineContext ctx, Next next) => middleware(ctx, next),
      for (final middleware in resolvedRoute)
        (EngineContext ctx, Next next) => middleware(ctx, next),
    ];
    chain.add((EngineContext ctx, Next next) async {
      try {
        // ignore: close_sinks, handed off to the registered WebSocket handler
        final webSocket = await WebSocketTransformer.upgrade(httpRequest);
        final wsContext = WebSocketContext(webSocket, ctx);

        await route.handler.onOpen(wsContext);

        webSocket.listen(
          (message) => route.handler.onMessage(wsContext, message),
          onDone: () => route.handler.onClose(wsContext),
          onError: (dynamic error) => route.handler.onError(wsContext, error),
          cancelOnError: false,
        );
      } catch (e) {
        httpRequest.response
          ..statusCode = HttpStatus.internalServerError
          ..write('WebSocket upgrade failed: $e')
          ..close();
      }
      return ctx.response;
    });

    final context = EngineContext(
      request: request,
      response: response,
      engine: this,
      handlers: chain,
      container: container,
    );

    container
      ..instance<Request>(request)
      ..instance<Response>(response)
      ..instance<EngineContext>(context);
    context
      ..set('routed.route_type', 'websocket')
      ..set('routed.route_path', route.path)
      ..set('routed.route_name', route.path);
    final manager = container.has<EventManager>()
        ? await container.make<EventManager>()
        : null;
    final eventRoute = EngineRoute(
      method: 'WEBSOCKET',
      path: route.path,
      handler: (ctx) => ctx.response,
      patternRegistry: _resolveRoutePatterns(),
    );

    manager?.publish(BeforeRoutingEvent(context));
    manager?.publish(RequestStartedEvent(context));
    manager?.publish(RouteMatchedEvent(context, eventRoute));

    try {
      await AppZone.run(
        engine: this,
        context: context,
        body: () async {
          await LoggingContext.run(this, context, (_) async {
            try {
              await context.run();
            } catch (err, stack) {
              manager?.publish(
                RoutingErrorEvent(context, eventRoute, err, stack),
              );
              await _handleGlobalError(context, err, stack);
            }
          });
        },
      );
    } finally {
      manager?.publish(AfterRoutingEvent(context, route: eventRoute));
      _onRequestFinished(request.id);
      manager?.publish(RequestFinishedEvent(context));
    }

    return request;
  }

  Future<bool> _runGlobalMiddlewares(
    HttpRequest httpRequest,
    Container container, {
    bool closeResponse = true,
    FutureOr<Response> Function(EngineContext ctx)? onComplete,
  }) async {
    if (middlewares.isEmpty) {
      return false;
    }

    final request = Request(httpRequest, {}, config);
    final response = Response(httpRequest.response);

    final resolvedGlobal = _resolveMiddlewares(middlewares, container);

    final handlers = <Middleware>[
      for (final middleware in resolvedGlobal)
        (EngineContext ctx, Next next) => middleware(ctx, next),
      (EngineContext ctx, Next next) async =>
          onComplete != null ? await onComplete(ctx) : ctx.response,
    ];

    final context = EngineContext(
      request: request,
      response: response,
      engine: this,
      handlers: handlers,
      container: container,
    );

    container
      ..instance<Request>(request)
      ..instance<Response>(response)
      ..instance<EngineContext>(context);

    final manager = container.has<EventManager>()
        ? await container.make<EventManager>()
        : null;

    manager?.publish(BeforeRoutingEvent(context));

    try {
      await AppZone.run(
        engine: this,
        context: context,
        body: () async {
          await LoggingContext.run(this, context, (logger) async {
            try {
              await context.run();
            } catch (err, stack) {
              await _handleGlobalError(context, err, stack);
            } finally {
              if (closeResponse && !response.isClosed) {
                response.close();
              }
            }
          });
        },
      );
    } finally {
      _onRequestFinished(request.id);
      manager?.publish(AfterRoutingEvent(context));
    }

    return true;
  }

  Set<String> _resolveAllowedMethods(String path, HttpRequest request) {
    final methods = <String>{};
    for (final route in _engineRoutes) {
      if (route.isFallback) {
        continue;
      }

      final pattern = route._uriPattern;
      final matchesPath =
          pattern.hasMatch(path) ||
          pattern.hasMatch(path.endsWith('/') ? path : '$path/');
      if (!matchesPath) {
        continue;
      }

      if (!route.validateConstraints(request)) {
        continue;
      }

      methods.add(route.method);
    }

    if (methods.contains('GET')) {
      methods.add('HEAD');
    }

    return methods;
  }

  void _writeAllowResponse(Object response, Set<String> methods, int status) {
    final ordered = methods.toList()..sort();
    final headerValue = ordered.join(', ');
    if (response is Response) {
      response.headers.set(HttpHeaders.allowHeader, headerValue);
      response.statusCode = status;
    } else if (response is HttpResponse) {
      response.headers.set(HttpHeaders.allowHeader, headerValue);
      response.statusCode = status;
    } else {
      throw StateError('Unsupported response type ${response.runtimeType}');
    }
  }

  void _writeOptionsResponse(Object response, Set<String> methods) {
    _writeAllowResponse(response, methods, HttpStatus.noContent);
  }

  void _writeMethodNotAllowedResponse(Object response, Set<String> methods) {
    _writeAllowResponse(response, methods, HttpStatus.methodNotAllowed);
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
  Future<void> _handleGlobalError(
    EngineContext ctx,
    Object err,
    StackTrace stack,
  ) async {
    final logger = LoggingContext.currentLogger();
    final errorPayload = <String, Object?>{
      'error_type': err.runtimeType.toString(),
      'error_message': err.toString(),
    };
    if (LoggingServiceProvider.includeStackTraces) {
      errorPayload['stack_trace'] = stack.toString();
    }
    final errorContext = contextual.Context(errorPayload);
    logger.error('Unhandled exception while processing request', errorContext);

    void reportHookError(Object hookError, StackTrace hookStack) {
      final hookPayload = <String, Object?>{
        'error_type': hookError.runtimeType.toString(),
        'error_message': hookError.toString(),
      };
      if (LoggingServiceProvider.includeStackTraces) {
        hookPayload['stack_trace'] = hookStack.toString();
      }
      logger.error(
        'Error hook threw while handling an exception',
        contextual.Context(hookPayload),
      );
    }

    await errorHooks.runBefore(ctx, err, stack, onHookError: reportHookError);

    var handled = await errorHooks.handle(
      ctx,
      err,
      stack,
      onHookError: reportHookError,
    );

    if (!handled &&
        err is HttpException &&
        err.message == 'Request body exceeds the maximum allowed size.') {
      ctx.string(
        'Request body exceeds the maximum allowed size.',
        statusCode: HttpStatus.requestEntityTooLarge,
      );
      handled = true;
    }

    if (!handled && err is ValidationError) {
      ctx.json(
        err.errors,
        statusCode: err.code ?? HttpStatus.unprocessableEntity,
      );
      handled = true;
    }

    if (!handled && err is EngineError && err.code != null) {
      if (!ctx.isClosed) {
        ctx.string(
          'EngineError(${err.code}): ${err.message}',
          statusCode: err.code!,
        );
      }
      handled = true;
    }

    if (!handled) {
      if (!ctx.isClosed) {
        ctx.string(
          'An unexpected error occurred. Please try again later.',
          statusCode: HttpStatus.internalServerError,
        );
      }
      handled = true;
    }

    if (!ctx.isAborted) {
      ctx.abort();
    }

    await errorHooks.runAfter(ctx, err, stack, onHookError: reportHookError);
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
        ? HttpStatus
              .movedPermanently // 301
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
