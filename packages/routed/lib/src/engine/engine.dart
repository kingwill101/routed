import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart' as fuzzy;
import 'package:meta/meta.dart' show visibleForTesting;
import 'package:routed/middlewares.dart';
import 'package:routed/src/config/config.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/contracts/config.dart/config.dart';
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/engine/engine_opt.dart';
import 'package:routed/src/middleware/cors.dart';
import 'package:routed/src/request.dart';
import 'package:routed/src/response.dart';
import 'package:routed/src/router/route_builder.dart';
import 'package:routed/src/router/router.dart';
import 'package:routed/src/router/router_group_builder.dart';
import 'package:routed/src/router/types.dart';
import 'package:routed/src/static_files.dart';
import 'package:routed/src/support/zone.dart';
import 'package:routed/wrapped_request.dart';
import 'package:http2/http2.dart';
import 'package:http2/multiprotocol_server.dart';

import '../middleware/csrf.dart';
import '../middleware/security_header.dart';

part 'engine_route.dart';
part 'engine_routing.dart';
part 'mount.dart';
part 'patterns.dart';
part 'request.dart';

/// The Engine is the core component of the Routed framework, responsible for
/// managing routers, middlewares, and handling incoming HTTP requests.
///
/// It allows mounting multiple routers under different prefixes, each with
/// optional engine-level middlewares. The `build()` method is then called
/// to produce a flattened route table for efficient request handling.
class Engine with StaticFileHandler {
  /// The configuration settings for this engine.
  final EngineConfig config;

  /// The application configuration, providing access to application-level settings.
  final Config _appConfig;

  /// Provides access to the application configuration.
  Config get appConfig => _appConfig;

  /// A list of [_EngineMount] objects, representing the mounted routers and their prefixes.
  final List<_EngineMount> _mounts = [];

  /// A list of [EngineRoute] objects, representing the flattened route table.
  final List<EngineRoute> _engineRoutes = [];

  /// A list of global middlewares that are applied to all routes handled by this engine.
  List<Middleware> middlewares;

  /// The HTTP server instance used to listen for incoming requests.
  HttpServer? _server;

  /// A flag indicating whether the routes have been initialized.
  bool _routesInitialized = false;

  /// The default router used when no other routers are explicitly mounted.
  final Router _defaultRouter = Router();

  /// Tracks active requests by their unique ID.
  final Map<String, Request> _activeRequests = {};

  /// Optional: Tracks the total number of requests handled by this engine.
  final int _totalRequests = 0;

  /// Returns the number of currently active requests.
  int get activeRequestCount => _activeRequests.length;

  /// Returns the total number of requests handled by this engine.
  int get totalRequests => _totalRequests;

  /// Creates a new [Engine] instance.
  ///
  /// The [config] parameter allows specifying an [EngineConfig] object to
  /// customize the engine's behavior. If not provided, a default [EngineConfig]
  /// is used.
  ///
  /// The [middlewares] parameter allows specifying a list of global middlewares
  /// to be applied to all routes. If not provided, an empty list is used.
  ///
  /// The [options] parameter allows specifying a list of [EngineOpt] functions
  /// to further configure the engine. These options are applied in order.
  ///
  /// The [configItems] parameter allows specifying a map of configuration
  /// items that can be accessed via the [appConfig] property.
  Engine({
    EngineConfig? config,
    List<Middleware>? middlewares,
    List<EngineOpt>? options,
    Map<String, dynamic>? configItems,
  })  : config = config ?? EngineConfig(),
        _appConfig = ConfigImpl(configItems ??
            {
              'app.name': 'Routed App',
              'app.env': 'production',
              'app.debug': false,
            }),
        middlewares = middlewares ?? [] {
    // Apply options in order
    options?.forEach((opt) => opt(this));
  }

  /// Creates a new [Engine] instance from an existing [Engine] instance.
  ///
  /// This factory method creates a deep copy of the provided [Engine],
  /// ensuring that all configuration and route information is preserved.
  factory Engine.from(Engine other) {
    final engine = Engine(config: other.config);
    engine._mounts.addAll(other._mounts);
    engine._engineRoutes.addAll(other._engineRoutes);
    engine.middlewares.addAll(other.middlewares);
    return engine;
  }

  /// Creates a default [Engine] instance with common options.
  ///
  /// This factory method creates an [Engine] with a default [EngineConfig]
  /// and a [timeoutMiddleware] with a duration of 30 seconds.
  factory Engine.d({
    EngineConfig? config,
    List<EngineOpt>? options,
  }) {
    return Engine(
      config: config ?? EngineConfig(),
      middlewares: [
        timeoutMiddleware(Duration(seconds: 30)),
      ],
      options: options,
    );
  }

  /// Gets the URL for a named route, substituting parameters if provided.
  ///
  /// The [name] parameter is the name of the route.
  /// The [params] parameter is an optional map of parameters to substitute into the route path.
  ///
  /// Returns the generated URL, or `null` if the route is not found.
  ///
  /// Throws:
  ///  - [Exception] if a route with the given name is not found.
  String? route(String name, [Map<String, dynamic>? params]) {
    _ensureRoutes();

    final route = _engineRoutes.firstWhere(
      (r) => r.name == name,
      orElse: () => throw Exception('Route with name "$name" not found'),
    );

    var path = route.path;

    if (params != null) {
      params.forEach((key, value) {
        // Replace both :param and {param} formats
        path = path
            .replaceAll(':$key', value.toString())
            .replaceAll('{$key}', value.toString());
      });
    }

    return path;
  }

  /// Attaches a [Router] to this engine at a given prefix.
  ///
  /// The [router] parameter is the [Router] instance to attach.
  /// The [prefix] parameter is the URL prefix at which the router will be mounted.
  /// The [middlewares] parameter is an optional list of engine-level middlewares that apply to this mount.
  Engine use(
    Router router, {
    String prefix = '',
    List<Middleware> middlewares = const [],
  }) {
    _mounts.add(_EngineMount(prefix, router, middlewares));
    return this;
  }

  /// Builds the final route table by flattening all mounted routers and their routes.
  ///
  /// This method performs the following steps:
  /// 1. For each mount, calls `router.build()` to build the router's route table.
  /// 2. For each route in the router, merges the mount prefix with the route path.
  /// 3. Combines engine-level middlewares with the route's final middlewares.
  ///
  /// The [parentGroupName] parameter is used for hierarchical route naming and is passed to child routers.
  void _build({String? parentGroupName}) {
    if (_routesInitialized) {
      _engineRoutes.clear();
    }

    if (config.features.enableSecurityFeatures) {
      middlewares.insertAll(0, [
        corsMiddleware(),
        csrfMiddleware(),
        securityHeadersMiddleware(),
        requestSizeLimitMiddleware(),
      ]);
    }
    // Build routes if not already done
    if (_engineRoutes.isEmpty) {
      use(_defaultRouter);
    }

    _engineRoutes.clear();

    for (final mount in _mounts) {
      // Let the child router finish its group & route merges
      mount.router
          .build(parentGroupName: parentGroupName, parentPrefix: mount.prefix);

      // Flatten all routes
      final childRoutes = mount.router.getAllRoutes();
      for (final r in childRoutes) {
        // Combine the mount prefix with the route path
        final combinedPath = _joinPaths(mount.prefix, r.path);

        // Engine-level + route's final
        final allMiddlewares = [...mount.middlewares, ...r.finalMiddlewares];

        _engineRoutes.add(
          EngineRoute(
            method: r.method,
            path: combinedPath,
            handler: r.handler,
            name: r.name,
            middlewares: allMiddlewares,
            constraints: r.constraints,
            isFallback: r.constraints['isFallback'] == true,
          ),
        );
      }
    }

    _routesInitialized = true;
  }

  /// Ensures that the routes have been built before accessing them.
  void _ensureRoutes() {
    if (!_routesInitialized) {
      _build();
    }
  }

  /// Returns an unmodifiable list of all final routes.
  List<EngineRoute> getAllRoutes() {
    _ensureRoutes();
    return List.unmodifiable(_engineRoutes);
  }

  /// Prints all routes to the console.
  void printRoutes() {
    for (final route in _engineRoutes) {
      print(route);
    }
  }

// same path-join logic as the router
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

  /// Gets a request by its unique ID.
  ///
  /// The [id] parameter is the unique identifier of the request.
  /// Returns the [Request] object if found, otherwise returns `null`.
  Request? getRequest(String id) => _activeRequests[id];

  /// Gets an unmodifiable list of all active requests.
  ///
  /// This method provides a snapshot of the currently active requests,
  /// which can be useful for monitoring or debugging purposes.
  List<Request> get activeRequests => List.unmodifiable(_activeRequests.values);

  /// Returns the default router.
  get defaultRouter => _defaultRouter;
}

Middleware requestSizeLimitMiddleware() {
  return (EngineContext ctx) async {
    final config = ctx.engineConfig;
    final maxRequestSize = config.security.maxRequestSize;

    if (maxRequestSize <= 0 || !config.features.enableSecurityFeatures) {
      // Disable the limit if maxRequestSize is zero or negative.
      await ctx.next();
      return;
    }

    final request = ctx.request.httpRequest;
    int totalBytesRead = 0;

    try {
      // Use a StreamTransformer to intercept the request body stream.
      final byteStream =
          request.cast<List<int>>(); // Ensure we have a byte stream

      final limitedStream = byteStream.transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (List<int> data, EventSink<List<int>> sink) {
            totalBytesRead += data.length;

            if (totalBytesRead > maxRequestSize) {
              // Exceeded the limit.  Abort the request.
              throw HttpException(
                  'Request body exceeds the maximum allowed size.');
            }

            // Pass the data along to the next handler.
            sink.add(data);
          },
          handleError:
              (Object error, StackTrace stackTrace, EventSink<List<int>> sink) {
            // Handle stream errors.  You might want to log this.
            sink.addError(error, stackTrace);
          },
          handleDone: (EventSink<List<int>> sink) {
            // Signal the end of the transformed stream.
            sink.close();
          },
        ),
      );

      await ctx.next();
    } catch (e) {
      ctx.abortWithStatus(
          HttpStatus.requestEntityTooLarge, 'Request body too large');
      //Close the connection to prevent further data transmission
      request.response.close();
      return;
    }
  };
}

extension SecureEngine on Engine {
  Future<void> serveSecure({
    String address = 'localhost',
    int port = 443,
    required String certificatePath,
    required String keyPath,
  }) async {
    final securityContext = SecurityContext()
      ..useCertificateChain(certificatePath)
      ..usePrivateKey(keyPath);

    final server = await MultiProtocolHttpServer.bind(
      address,
      port,
      securityContext,
    );

    print('Secure server listening on https://$address:$port');

    server.startServing(
      // HTTP/1.1 handler
      (request) async {
        await handleRequest(request);
      },
      // HTTP/2 handler
      (stream) async {
        throw UnimplementedError();
        // await processStream(stream);
      },
    );
  }

  Future<void> processStream(ServerTransportStream stream) async {
    
    await for (var message in stream.incomingMessages) {
      if (message is HeadersStreamMessage) {
        final headers = <String, String>{};
        for (var header in message.headers) {
          final name = utf8.decode(header.name);
          final value = utf8.decode(header.value);
          headers[name] = value;
        }

        final method = headers[':method']!;
        final path = headers[':path']!;
        final scheme = headers[':scheme']!;
        final authority = headers[':authority']!;

        final uri = Uri.parse('$scheme://$authority$path');

        // final request = Request(method, uri, headers: headers);

        // await handleRequest(request);

        // // Send response
        // final responseHeaders = [
        //   Header.ascii(':status', ctx.response.statusCode.toString()),
        //   ...ctx.response.headers.entries.map(
        //     (e) => Header.ascii(e.key, e.value)
        //   ),
        // ];

        // stream.sendHeaders(responseHeaders);
        // await stream.sendData(ctx.response.bodyBytes);
      }
    }
  }
}
