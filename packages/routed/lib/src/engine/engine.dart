import 'dart:async';
import 'dart:io';

import 'package:fuzzywuzzy/fuzzywuzzy.dart' as fuzzy;
import 'package:routed/middlewares.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/request.dart';
import 'package:routed/src/response.dart';
import 'package:routed/src/router/route_builder.dart';
import 'package:routed/src/router/router.dart';
import 'package:routed/src/router/router_group_builder.dart';
import 'package:routed/src/router/types.dart';
import 'package:routed/src/engine/engine_opt.dart';

part 'engine_route.dart';
part 'engine_routing.dart';
part 'mount.dart';
part 'patterns.dart';
part 'request.dart';

/// The Engine class is responsible for managing multiple routers, each of which
/// can be mounted under different prefixes. It also supports optional "engine-level"
/// middlewares that apply to all routes within the engine. After configuring the routers
/// and middlewares, you call the `build()` method to produce a flattened route table.
class Engine {
  /// Configuration settings for the engine.
  final EngineConfig config;

  /// List of mounted routers with their associated prefixes and middlewares.
  final List<_EngineMount> _mounts = [];

  /// List of all routes managed by the engine.
  final List<EngineRoute> _engineRoutes = [];

  /// List of middlewares that apply to all routes within the engine.
  List<Middleware> middlewares;

  /// The HTTP server instance.
  HttpServer? _server;

  /// Flag to indicate whether the routes have been initialized.
  bool _routesInitialized = false;

  /// Default router instance.
  final Router _defaultRouter = Router();

  /// Map to track active requests by their ID.
  final Map<String, Request> _activeRequests = {};

  /// Total number of requests handled by the engine.
  int _totalRequests = 0;

  /// Getter to retrieve the count of active requests.
  int get activeRequestCount => _activeRequests.length;

  /// Getter to retrieve the total number of requests handled.
  int get totalRequests => _totalRequests;

  /// Constructor for the Engine class.
  ///
  /// [config] - Optional configuration settings for the engine.
  /// [middlewares] - Optional list of middlewares to apply to all routes.
  /// [options] - Optional list of engine options to apply.
  Engine({
    EngineConfig? config,
    List<Middleware>? middlewares,
    List<EngineOpt>? options,
  })  : config = config ?? EngineConfig(),
        middlewares = middlewares ?? [] {
    // Apply options in order
    options?.forEach((opt) => opt(this));
  }

  /// Factory constructor to create a new Engine instance from an existing one.
  ///
  /// [other] - The existing Engine instance to copy.
  factory Engine.from(Engine other) {
    final engine = Engine(config: other.config);
    engine._mounts.addAll(other._mounts);
    engine._engineRoutes.addAll(other._engineRoutes);
    engine.middlewares.addAll(other.middlewares);
    return engine;
  }

  /// Factory constructor to create a default Engine instance with common options.
  ///
  /// [config] - Optional configuration settings for the engine.
  /// [options] - Optional list of engine options to apply.
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

  /// Attach a router at a given prefix, with optional engine-level middlewares.
  ///
  /// [router] - The router to attach.
  /// [prefix] - The prefix under which to mount the router.
  /// [middlewares] - Optional list of middlewares to apply to the router.
  Engine use(
    Router router, {
    String prefix = '',
    List<Middleware> middlewares = const [],
  }) {
    _mounts.add(_EngineMount(prefix, router, middlewares));
    return this;
  }

  /// Build the final route table by merging routes from all mounted routers.
  ///
  /// [parentGroupName] - Optional parent group name for route grouping.
  void _build({String? parentGroupName}) {
    if (_routesInitialized) {
      _engineRoutes.clear();
    }

    if (_mounts.isEmpty) {
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

  /// Ensure that the routes are built and initialized.
  void _ensureRoutes() {
    if (!_routesInitialized) {
      _build();
    }
  }

  /// Return all final routes managed by the engine.
  List<EngineRoute> getAllRoutes() {
    _ensureRoutes();
    return List.unmodifiable(_engineRoutes);
  }

  /// Print all routes managed by the engine to the console.
  void printRoutes() {
    for (final route in _engineRoutes) {
      print(route);
    }
  }

  /// Join two paths, ensuring proper handling of slashes.
  ///
  /// [base] - The base path.
  /// [child] - The child path to append to the base path.
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

  // Add ability to get request by ID
  Request? getRequest(String id) => _activeRequests[id];

  // Add ability to get all active requests (e.g., for admin/monitoring)
  List<Request> get activeRequests => List.unmodifiable(_activeRequests.values);

  get defaultRouter => _defaultRouter;
}
