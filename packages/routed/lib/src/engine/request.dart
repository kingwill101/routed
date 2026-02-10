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
    Container rootContainer,
    Container Function() ensureRequestContainer,
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

    Object? maxRequestSizeSetting;
    if (rootContainer.has<Config>()) {
      final configMap = rootContainer.get<Config>();
      maxRequestSizeSetting = configMap.get<Object?>(
        'security.max_request_size',
      );
    }
    final maxRequestSize = maxRequestSizeSetting is int
        ? maxRequestSizeSetting
        : config.security.maxRequestSize;

    final HttpRequest effectiveRequest = maxRequestSize > 0
        ? WrappedRequest(httpRequest, maxRequestSize)
        : httpRequest;

    final normalizedPath = _normalizePath(path);
    final candidateRoutes = _routesByMethod[method] ?? const <EngineRoute>[];
    final bool useTrie = config.features.enableTrieRouting;
    final RouteTrie? trie = useTrie ? _trieByMethod[method] : null;

    bool matchesCurrentPath = false;
    EngineRoute? matchedRoute;

    final staticRoutes = _staticRoutesByMethod[method];
    final staticMatch = staticRoutes?[normalizedPath];
    if (staticMatch != null) {
      matchesCurrentPath = true;
      if (staticMatch.validateConstraints(effectiveRequest)) {
        matchedRoute = staticMatch;
      }
    }

    if (matchedRoute == null && trie != null) {
      final trieResult = trie.match(normalizedPath, effectiveRequest);
      if (trieResult.pathMatched) {
        matchesCurrentPath = true;
      }
      matchedRoute = trieResult.route;
    }

    if (matchedRoute == null && trie == null) {
      for (final candidate in candidateRoutes) {
        if (!candidate.matchesPath(normalizedPath, allowTrailingSlash: false)) {
          continue;
        }
        matchesCurrentPath = true;
        if (candidate.validateConstraints(effectiveRequest)) {
          matchedRoute = candidate;
          break;
        }
      }
    }

    // Handle trailing slash redirects only when the current path does not match.
    if (config.redirectTrailingSlash && !matchesCurrentPath) {
      final alternativePath = EngineRoute._alternatePath(normalizedPath);
      EngineRoute? alternativeMatch;
      if (alternativePath != normalizedPath) {
        alternativeMatch = staticRoutes?[alternativePath];
        if (alternativeMatch == null && trie != null) {
          alternativeMatch = trie
              .match(alternativePath, effectiveRequest)
              .route;
        }
        alternativeMatch ??= candidateRoutes.firstWhereOrNull(
          (candidate) => candidate.matchesPath(alternativePath),
        );
      }

      if (alternativeMatch != null) {
        final manager = await _resolveEventManager(rootContainer);
        if (manager != null) {
          final container = ensureRequestContainer();
          final nfRequest = Request(
            effectiveRequest,
            const <String, dynamic>{},
            config,
          );
          final nfResponse = Response(effectiveRequest.response);
          _bindRequestScope(container, nfRequest, nfResponse);
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
        await _drainHttpRequestIfNeeded(effectiveRequest);
        await effectiveRequest.response.close();
        return null;
      }
    }

    if (matchedRoute != null) {
      try {
        return await _handleMatchedRoute(
          matchedRoute,
          effectiveRequest,
          ensureRequestContainer(),
        );
      } on HttpException catch (e) {
        if (e.message == 'Request body exceeds the maximum allowed size.') {
          effectiveRequest.response.statusCode =
              HttpStatus.requestEntityTooLarge;
          effectiveRequest.response.write(
            'Request body exceeds the maximum allowed size.',
          );
          await _drainHttpRequestIfNeeded(effectiveRequest);
          await effectiveRequest.response.close();
          return null;
        }
        rethrow;
      }
    }
    // Automatic OPTIONS handling when enabled and no explicit handler was found.
    if (method == 'OPTIONS' && config.defaultOptionsEnabled) {
      final allowed = _resolveAllowedMethods(normalizedPath, effectiveRequest);
      if (allowed.isNotEmpty) {
        allowed.add('OPTIONS');
        if (_cachedGlobalMiddlewares.isNotEmpty) {
          await _runGlobalMiddlewares(
            effectiveRequest,
            ensureRequestContainer(),
            onComplete: (ctx) async {
              _writeOptionsResponse(ctx.response, allowed);
              return ctx.response;
            },
          );
        } else {
          _writeOptionsResponse(effectiveRequest.response, allowed);
          await _drainHttpRequestIfNeeded(effectiveRequest);
          await effectiveRequest.response.close();
        }
        return null;
      }
    }

    // Third pass: handle method not allowed
    if (config.handleMethodNotAllowed) {
      final allowedMethods = _resolveAllowedMethods(
        normalizedPath,
        effectiveRequest,
      );

      if (allowedMethods.isNotEmpty) {
        allowedMethods.add('OPTIONS');

        if (method == 'OPTIONS' && _cachedGlobalMiddlewares.isNotEmpty) {
          await _runGlobalMiddlewares(
            effectiveRequest,
            ensureRequestContainer(),
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
        await _drainHttpRequestIfNeeded(effectiveRequest);
        await effectiveRequest.response.close();
        return null;
      }
    }

    // Fourth pass: check for fallback routes if no other match was found
    final fallbackCandidates = <EngineRoute>[
      ...?_fallbackRoutesByMethod[method],
      ...?_fallbackRoutesByMethod['*'],
    ];
    if (fallbackCandidates.isNotEmpty) {
      // Find the most specific fallback route using fuzzy matching
      EngineRoute? mostSpecificFallback;
      int maxSimilarityScore = 0;

      for (final fallbackRoute in fallbackCandidates) {
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
          ensureRequestContainer(),
        );
      }
    }

    // No matches found
    return await _respondWithNotFound(
      effectiveRequest,
      ensureRequestContainer(),
    );
  }

  Future<Request> _respondWithNotFound(
    HttpRequest httpRequest,
    Container container,
  ) async {
    final request = Request(httpRequest, const <String, dynamic>{}, config);
    final response = Response(httpRequest.response);

    _onRequestStarted(request);

    final handlers = <Middleware>[..._resolveGlobalMiddlewares(container)];
    handlers.add((EngineContext ctx, Next next) async {
      if (!ctx.response.isClosed) {
        ctx.errorResponse(
          statusCode: HttpStatus.notFound,
          message: 'Not Found',
        );
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

    _bindRequestScope(container, request, response, context);

    context
      ..set('routed.route_type', 'http')
      ..set('routed.route_name', 'routed.404')
      ..set('routed.route_path', httpRequest.uri.path);

    final manager = await _resolveEventManager(container);

    manager?.publish(BeforeRoutingEvent(context));
    manager?.publish(RequestStartedEvent(context));
    manager?.publish(RouteNotFoundEvent(context));

    try {
      await _runInRequestZone(
        context: context,
        body: () async {
          await _runWithLogging(container, context, () async {
            try {
              await context.run();
            } catch (err, stack) {
              manager?.publish(RoutingErrorEvent(context, null, err, stack));
              await _handleGlobalError(context, err, stack);
            } finally {
              await _drainRequestIfNeeded(request, context);
              if (!response.isClosed) {
                await response.close();
              }
              // Publish after-request events before the response is fully transmitted
              manager?.publish(AfterRoutingEvent(context));
              manager?.publish(RequestFinishedEvent(context));
            }
          });
        },
      );
    } finally {
      _onRequestFinished(request.id);
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
    final request = Request(httpRequest, const <String, dynamic>{}, config);
    final response = Response(httpRequest.response);

    _onRequestStarted(request);

    final handlers =
        (_globalHasMiddlewareReferences || route.hasMiddlewareReference)
        ? route.composeHandlers(
            _resolveGlobalMiddlewares(container),
            _resolveRouteMiddlewares(route, container),
          )
        : route.cachedHandlers;

    final context = EngineContext(
      request: request,
      response: response,
      route: route,
      engine: this,
      handlers: handlers,
      container: container,
    );

    _bindRequestScope(container, request, response, context);

    context.set('routed.route_type', 'http');
    context.set('routed.route_name', route.name ?? route.path);
    context.set('routed.route_path', route.path);

    final manager = await _resolveEventManager(container);

    manager?.publish(BeforeRoutingEvent(context));
    manager?.publish(RequestStartedEvent(context));

    try {
      await _runInRequestZone(
        context: context,
        body: () async {
          await _runWithLogging(container, context, () async {
            try {
              manager?.publish(RouteMatchedEvent(context, route));
              await context.run();
            } catch (err, stack) {
              manager?.publish(RoutingErrorEvent(context, route, err, stack));
              await _handleGlobalError(context, err, stack);
            } finally {
              await _drainRequestIfNeeded(request, context);
              // Close if our wrapper not yet closed; underlying may already be
              // closed by direct HttpResponse usage (e.g. static file handler).
              if (!response.isClosed) {
                await response.close();
              }
              // Publish after-request events before the response is fully transmitted
              manager?.publish(AfterRoutingEvent(context, route: route));
              manager?.publish(RequestFinishedEvent(context));
            }
          });
        },
      );
    } catch (err, stack) {
      // Anything that wasn't caught at a lower level gets caught here.
      await _handleGlobalError(context, err, stack);
    } finally {
      _onRequestFinished(request.id);
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
      pathParameters.isEmpty
          ? const <String, dynamic>{}
          : Map<String, dynamic>.from(pathParameters),
      config,
    );
    final response = Response(httpRequest.response);
    _onRequestStarted(request);

    final List<Middleware> chain = [
      ..._cachedGlobalMiddlewares,
      ...route.middlewares,
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

    _bindRequestScope(container, request, response, context);
    context
      ..set('routed.route_type', 'websocket')
      ..set('routed.route_path', route.path)
      ..set('routed.route_name', route.path);
    final manager = await _resolveEventManager(container);
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
      await _runInRequestZone(
        context: context,
        body: () async {
          await _runWithLogging(container, context, () async {
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
    if (_cachedGlobalMiddlewares.isEmpty) {
      return false;
    }

    final request = Request(httpRequest, const <String, dynamic>{}, config);
    final response = Response(httpRequest.response);

    final handlers = <Middleware>[
      ..._resolveGlobalMiddlewares(container),
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

    _bindRequestScope(container, request, response, context);

    final manager = await _resolveEventManager(container);

    manager?.publish(BeforeRoutingEvent(context));

    try {
      await _runInRequestZone(
        context: context,
        body: () async {
          await _runWithLogging(container, context, () async {
            try {
              await context.run();
            } catch (err, stack) {
              await _handleGlobalError(context, err, stack);
            } finally {
              await _drainRequestIfNeeded(request, context);
              if (closeResponse && !response.isClosed) {
                await response.close();
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
    final normalizedPath = _normalizePath(path);
    final allowTrailingSlash = config.redirectTrailingSlash;
    final altPath = allowTrailingSlash
        ? EngineRoute._alternatePath(normalizedPath)
        : normalizedPath;

    for (final entry in _routesByMethod.entries) {
      final method = entry.key;
      final routes = entry.value;

      final staticRoutes = _staticRoutesByMethod[method];
      var staticRoute = staticRoutes?[normalizedPath];
      if (staticRoute == null && allowTrailingSlash) {
        staticRoute = staticRoutes?[altPath];
      }
      if (staticRoute != null && staticRoute.validateConstraints(request)) {
        methods.add(method);
        continue;
      }

      for (final route in routes) {
        if (!route.matchesPath(
          normalizedPath,
          allowTrailingSlash: allowTrailingSlash,
        )) {
          continue;
        }
        if (!route.validateConstraints(request)) {
          continue;
        }
        methods.add(method);
        break;
      }
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
    final logger = LoggingContext.currentLogger(ctx);
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
      ctx.errorResponse(
        statusCode: HttpStatus.requestEntityTooLarge,
        message: 'Request body exceeds the maximum allowed size.',
      );
      handled = true;
    }

    if (!handled && err is ValidationError) {
      ctx.errorResponse(
        statusCode: err.code ?? HttpStatus.unprocessableEntity,
        message: err.message,
        jsonBody: err.errors,
      );
      handled = true;
    }

    if (!handled && err is EngineError && err.code != null) {
      if (!ctx.isClosed) {
        ctx.errorResponse(
          statusCode: err.code!,
          message: err.message,
          jsonBody: err.toJson(),
        );
      }
      handled = true;
    }

    if (!handled) {
      if (!ctx.isClosed) {
        ctx.errorResponse(
          statusCode: HttpStatus.internalServerError,
          message: 'An unexpected error occurred. Please try again later.',
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

  Future<void> _drainHttpRequestIfNeeded(HttpRequest request) async {
    final length = request.contentLength;
    if (length == 0) return;
    if (length < 0 && !request.headers.chunkedTransferEncoding) return;
    request.response.headers.set(HttpHeaders.connectionHeader, 'close');
  }

  Future<void> _drainRequestIfNeeded(
    Request request,
    EngineContext context,
  ) async {
    if (context.isUpgraded) return;
    if (request.bodyConsumed) return; // Already consumed, nothing to drain
    if (!request.hasBody) return;
    // Body exists but wasn't consumed - drain it or close connection
    try {
      await request.drain();
    } catch (_) {
      // If drain fails, signal connection close
      context.response.headers.set(HttpHeaders.connectionHeader, 'close');
    }
  }

  bool _isReadOnlyContainer(Container container) {
    return container is ReadOnlyContainer;
  }

  void _bindRequestScope(
    Container container,
    Request request,
    Response response, [
    EngineContext? context,
  ]) {
    if (_isReadOnlyContainer(container)) {
      final engineContext =
          context ??
          EngineContext(
            request: request,
            response: response,
            engine: this,
            container: container,
          );
      requestScopeExpando[request.httpRequest] = RequestScope(
        request: request,
        response: response,
        context: engineContext,
      );
      return;
    }
    if (context != null) {
      container
        ..instance<Request>(request)
        ..instance<Response>(response)
        ..instance<EngineContext>(context);
    } else {
      container
        ..instance<Request>(request)
        ..instance<Response>(response);
    }
  }

  Future<void> _runWithLogging(
    Container container,
    EngineContext context,
    Future<void> Function() body,
  ) async {
    if (_isLoggingEnabled(container)) {
      await LoggingContext.run(this, context, (_) async {
        await body();
      });
      return;
    }
    await body();
  }

  Future<void> _runInRequestZone({
    required EngineContext context,
    required Future<void> Function() body,
  }) async {
    // TEMP: disable AppZone wrapping to identify zone dependencies.
    // await AppZone.run(body: body, engine: this, context: context);
    await body();
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
