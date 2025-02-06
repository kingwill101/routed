import 'dart:async';
import 'dart:io';

import 'package:fuzzywuzzy/fuzzywuzzy.dart' as fuzzy;
import 'package:routed/middlewares.dart';
import 'package:routed/src/config/config.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/contracts/config.dart/config.dart';
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/engine/engine_opt.dart';
import 'package:routed/src/request.dart';
import 'package:routed/src/response.dart';
import 'package:routed/src/router/route_builder.dart';
import 'package:routed/src/router/router.dart';
import 'package:routed/src/router/router_group_builder.dart';
import 'package:routed/src/router/types.dart';
import 'package:meta/meta.dart' show visibleForTesting;

part 'engine_route.dart';
part 'engine_routing.dart';
part 'mount.dart';
part 'patterns.dart';
part 'request.dart';

/// The Engine can mount multiple routers under different prefixes,
/// each with optional "engine-level" middlewares.
/// Then you call build() to produce a flattened route table.
class Engine {
  final EngineConfig config;
  final Config _appConfig;

  Config get appConfig => _appConfig;
  final List<_EngineMount> _mounts = [];
  final List<EngineRoute> _engineRoutes = [];
  List<Middleware> middlewares;
  HttpServer? _server;
  bool _routesInitialized = false;
  final Router _defaultRouter = Router();

  // Track active requests
  final Map<String, Request> _activeRequests = {};

  // Optional: Track request metrics
  int _totalRequests = 0;

  int get activeRequestCount => _activeRequests.length;

  int get totalRequests => _totalRequests;

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

  factory Engine.from(Engine other) {
    final engine = Engine(config: other.config);
    engine._mounts.addAll(other._mounts);
    engine._engineRoutes.addAll(other._engineRoutes);
    engine.middlewares.addAll(other.middlewares);
    return engine;
  }

  // Factory for default engine with common options
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

  /// Get route URL by name with optional parameters
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

  /// Attach a router at a given prefix, with optional engine-level middlewares
  Engine use(
    Router router, {
    String prefix = '',
    List<Middleware> middlewares = const [],
  }) {
    _mounts.add(_EngineMount(prefix, router, middlewares));
    return this;
  }

  /// Build the final route table:
  /// 1) For each mount, call `router.build()`
  /// 2) For each route in the router, merge with the prefix
  /// 3) Combine engine-level middlewares with the route's finalMiddlewares
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

  _ensureRoutes() {
    if (!_routesInitialized) {
      _build();
    }
  }

  /// Return all final routes
  List<EngineRoute> getAllRoutes() {
    _ensureRoutes();
    return List.unmodifiable(_engineRoutes);
  }

  /// Print them
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

  // Add ability to get request by ID
  Request? getRequest(String id) => _activeRequests[id];

  // Add ability to get all active requests (e.g., for admin/monitoring)
  List<Request> get activeRequests => List.unmodifiable(_activeRequests.values);

  get defaultRouter => _defaultRouter;
}
