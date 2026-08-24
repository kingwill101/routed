import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart' as fuzzy;
import 'package:http2/http2.dart' as http2;
import 'package:meta/meta.dart' show internal, visibleForTesting;
import 'package:routed_core/src/config/typed.dart';
import 'package:routed_core/src/container/container.dart';
import 'package:routed_core/src/container/container_mixin.dart';
import 'package:routed_core/src/container/read_only_container.dart';
import 'package:routed_core/src/context/context.dart';
import 'package:routed_core/src/engine/config.dart';
import 'package:routed_core/src/engine/engine_opt.dart';
import 'package:routed_core/src/engine/events/request.dart';
import 'package:routed_core/src/engine/events/route.dart';
import 'package:routed_core/src/engine/http2_server.dart';
import 'package:routed_core/src/engine/middleware_registry.dart';
import 'package:routed_core/src/engine/providers/core.dart';
import 'package:routed_core/src/engine/providers/registry.dart';
import 'package:routed_core/src/engine/providers/routing.dart';
import 'package:routed_core/src/engine/request_scope.dart';
import 'package:routed_core/src/engine/route_match.dart';
import 'package:routed_core/src/engine/wrapped_request.dart';
import 'package:routed_core/src/events/event_manager.dart';
import 'package:routed_core/src/http/adapter_http.dart';
import 'package:routed_core/src/http/constraint_request.dart';
import 'package:routed_core/src/http/portable_message.dart';
import 'package:routed_core/src/http/transport.dart';
import 'package:routed_core/src/provider/provider.dart';
import 'package:routed_core/src/request.dart';
import 'package:routed_core/src/response.dart';
import 'package:routed_core/src/router/middleware_reference.dart';
import 'package:routed_core/src/router/route_metadata.dart';
import 'package:routed_core/src/router/router.dart';
import 'package:routed_core/src/router/router_group_builder.dart';
import 'package:routed_core/src/router/types.dart';
import 'package:routed_core/src/runtime/shutdown.dart';
import 'package:routed_core/src/support/named_registry.dart';
import 'package:routed_core/src/utils/debug.dart';
import 'package:routed_core/src/websocket/websocket_handler.dart';

export 'events/events.dart';

part 'engine_route.dart';
part 'engine_routing.dart';
part 'error_handling.dart';
part 'mount.dart';
part 'param_utils.dart';
part 'patterns.dart';
part 'request.dart';
part 'route_trie.dart';

/// The core HTTP engine of the Routed framework.
///
/// The [Engine] is responsible for managing the complete HTTP request lifecycle,
/// including routing, middleware execution, static file serving, WebSocket
/// connections, and error handling. It serves as the central orchestrator for
/// all incoming HTTP requests and their corresponding responses.
///
/// ## Features
///
/// - **Flexible Routing**: Register routes with path parameters, constraints,
///   and HTTP method validation
/// - **Middleware Pipeline**: Apply global, group, and route-specific middleware
/// - **Static File Serving**: Serve static assets from directories or disk storage
/// - **WebSocket Support**: Handle WebSocket connections with middleware
/// - **Service Providers**: Extensible architecture through service providers
/// - **Configuration**: Provider-owned typed configuration validated at startup
/// - **HTTP/2 Support**: Optional HTTP/2 protocol support with multiplexing
/// - **Graceful Shutdown**: Handle shutdown signals with configurable grace periods
///
/// ## Basic Usage (Bare Mode)
///
/// ```dart
/// // Minimal engine - no providers, no file I/O
/// final engine = Engine();
///
/// engine.get('/hello', (ctx) => ctx.string('Hello, World!'));
/// await engine.serve();
/// ```
///
/// ## With Default Providers
///
/// ```dart
/// // Core + routing services with typed configuration
/// final engine = Engine(providers: Engine.defaultProviders);
///
/// engine.get('/users/{id}', (ctx) {
///   final id = ctx.params['id'];
///   return ctx.json({'user': id});
/// });
///
/// await engine.initialize();
/// await engine.serve();
/// ```
///
/// ## Custom Provider Composition
///
/// ```dart
/// final engine = Engine(
///   providers: [
///     ...Engine.defaultProviders,
///     DatabaseServiceProvider(),
///     CacheServiceProvider(),
///   ],
///   options: [withMiddleware([requestIdMiddleware()])],
/// );
/// ```
///
/// ## Service Providers
///
/// Extend the engine with custom service providers:
///
/// ```dart
/// class DatabaseServiceProvider extends ServiceProvider {
///   @override
///   void register(Container container) {
///     container.singleton<Database>((c) async => Database());
///   }
///
///   @override
///   Future<void> boot(Container container) async {
///     final db = await container.make<Database>();
///     await db.connect();
///   }
/// }
///
/// final engine = Engine(providers: [DatabaseServiceProvider()]);
/// ```
class Engine with ContainerMixin {
  /// Creates a new [Engine] instance with the given configuration.
  ///
  /// All parameters are optional and have sensible defaults for typical applications.
  ///
  /// ## Parameters
  ///
  /// - [config]: An [EngineConfig] object to customize core engine behavior
  ///   including security, routing, and TLS settings.
  ///
  /// - [middlewares]: Global middleware applied to all routes. These execute
  ///   before any route-specific middleware.
  ///
  /// - [options]: A list of [EngineOpt] functions for additional configuration.
  ///   These are applied in sequence after providers are registered.
  ///
  /// - [errorHandling]: Customize error handling behavior through an
  ///   [ErrorHandlingRegistry]. If not provided, a default registry is used.
  ///
  /// - [providers]: Service providers to register. Use [Engine.defaultProviders]
  ///   for the core + routing profile.
  ///
  /// ## Examples
  ///
  /// Bare engine (minimal, no providers):
  /// ```dart
  /// final engine = Engine();
  /// engine.get('/hello', (ctx) => ctx.string('Hello'));
  /// ```
  ///
  /// Core engine with the default core providers:
  /// ```dart
  /// final engine = Engine(providers: Engine.defaultProviders);
  /// await engine.initialize();
  /// ```
  ///
  /// Custom core-provider composition:
  /// ```dart
  /// final engine = Engine(
  ///   config: EngineConfig(
  ///     security: EngineSecurityFeatures(maxRequestSize: 5 * 1024 * 1024),
  ///   ),
  ///   providers: [
  ///     CoreServiceProvider(
  ///       EngineConfig(
  ///         security: EngineSecurityFeatures(maxRequestSize: 5 * 1024 * 1024),
  ///       ),
  ///     ),
  ///     RoutingServiceProvider(),
  ///   ],
  /// );
  /// ```
  Engine({
    EngineConfig? config,
    RuntimeContext? runtime,
    List<Middleware>? middlewares,
    List<EngineOpt>? options,
    ErrorHandlingRegistry? errorHandling,
    List<ServiceProvider>? providers,
  }) : middlewares = middlewares ?? [],
       errorHooks = errorHandling?.clone() ?? ErrorHandlingRegistry() {
    setRuntimeContext(runtime ?? RuntimeContext());
    _registerBareDefaults(config: config);

    final effectiveProviders = <ServiceProvider>[...?providers];
    if (config != null) {
      final coreIndex = effectiveProviders.indexWhere(
        (provider) => provider is CoreServiceProvider,
      );
      if (coreIndex >= 0) {
        effectiveProviders[coreIndex] = CoreServiceProvider(config);
      }
    }

    if (effectiveProviders.isNotEmpty) {
      for (final provider in effectiveProviders) {
        // Skip duplicate provider types to prevent overwriting config
        if (_registeredProviderTypes.contains(provider.runtimeType)) {
          continue;
        }
        registerProvider(provider);
        _registeredProviderTypes.add(provider.runtimeType);
      }
    }

    // Apply options in order
    options?.forEach((opt) => opt(this));
    _rebuildMiddlewareStacks();
  }

  /// Creates a new engine instance from an existing engine.
  ///
  /// This factory creates a copy of [other], preserving its configuration,
  /// routes, middlewares, and error handling settings. Useful for creating
  /// variations of an engine with modified settings.
  ///
  /// Note: Providers are not copied. If you need the same providers, pass them
  /// explicitly or copy them from the source engine's container.
  ///
  /// Example:
  /// ```dart
  /// final baseEngine = Engine(
  ///   config: EngineConfig(redirectTrailingSlash: true),
  /// );
  /// final testEngine = Engine.from(baseEngine);
  /// ```
  factory Engine.from(Engine other) {
    final engine = Engine(
      config: other.config,
      errorHandling: other.errorHooks,
    );
    if (other.container.has<RoutePatternRegistry>()) {
      final registry = other.container.get<RoutePatternRegistry>();
      engine.container.instance<RoutePatternRegistry>(
        RoutePatternRegistry.clone(registry),
      );
    }
    engine._mounts.addAll(other._mounts);
    engine._engineRoutes.addAll(other._engineRoutes);
    engine.middlewares.addAll(other.middlewares);
    return engine;
  }

  /// Creates an engine instance with the default core providers and common
  /// production configuration hooks.
  ///
  /// Example:
  /// ```dart
  /// final engine = Engine.d(
  ///   config: EngineConfig(
  ///     security: EngineSecurityFeatures(maxRequestSize: 10 * 1024 * 1024),
  ///   ),
  ///   providers: [
  ///     CoreServiceProvider(
  ///       EngineConfig(
  ///         security: EngineSecurityFeatures(
  ///           cors: CorsConfig(enabled: true),
  ///         ),
  ///       ),
  ///     ),
  ///     RoutingServiceProvider(),
  ///   ],
  /// );
  /// ```
  factory Engine.d({EngineConfig? config, List<EngineOpt>? options}) {
    return Engine(
      config: config ?? EngineConfig(),
      middlewares: [],
      options: options,
      providers: Engine.defaultProviders,
    );
  }

  /// The default providers for a full-featured engine.
  ///
  /// Includes:
  /// - [CoreServiceProvider] - typed engine configuration and core bindings
  /// - [RoutingServiceProvider] - Event manager, signals, and routing config
  ///
  /// Use this for most applications:
  /// ```dart
  /// final engine = Engine(providers: Engine.defaultProviders);
  /// ```
  ///
  static List<ServiceProvider> get defaultProviders => [
    CoreServiceProvider(),
    RoutingServiceProvider(),
  ];

  /// Returns all built-in service providers registered with the framework.
  ///
  /// This includes all providers currently registered in [ProviderRegistry]
  /// (foundation defaults plus any adapters that called `register`).
  ///
  /// Use this when you want a fully-featured engine with all framework capabilities:
  ///
  /// ```dart
  /// final engine = Engine(providers: Engine.builtins);
  /// await engine.initialize();
  /// ```
  ///
  /// For most applications, [defaultProviders] (core + routing) is sufficient.
  /// Use [builtins] when you need the complete feature set without manually
  /// listing each provider.
  ///
  /// See also:
  /// - [defaultProviders] for minimal setup (core + routing only)
  /// - [ProviderRegistry] for the full list of registered providers
  static List<ServiceProvider> get builtins => ProviderRegistry
      .instance
      .registrations
      .map((r) => r.factory())
      .toList(growable: false);
  bool _closed = false;

  /// Whether [close] has been called on this engine.
  bool get isClosed => _closed;

  /// The configuration settings for this engine.
  EngineConfig get config => container.get();

  /// A list of [_EngineMount] objects, representing the mounted routers and their prefixes.
  final List<_EngineMount> _mounts = [];

  /// A list of [EngineRoute] objects, representing the flattened route table.
  final List<EngineRoute> _engineRoutes = [];

  /// Routes indexed by HTTP method for faster lookup.
  final Map<String, List<EngineRoute>> _routesByMethod = {};

  /// Static routes indexed by method and path for O(1) lookup.
  final Map<String, Map<String, EngineRoute>> _staticRoutesByMethod = {};

  /// Optional segment-trie routers indexed by HTTP method.
  final Map<String, RouteTrie> _trieByMethod = {};

  /// Fallback routes collected during build.
  final List<EngineRoute> _fallbackRoutes = [];
  final Map<String, List<EngineRoute>> _fallbackRoutesByMethod = {};

  /// Map for quick lookup of routes by their name once the routing table is frozen.
  Map<String, EngineRoute> _routesByName = {};

  /// A list of global middlewares that are applied to all routes handled by this engine.
  List<Middleware> middlewares;

  /// Cached resolved global middlewares built with the routing table.
  List<Middleware> _cachedGlobalMiddlewares = const <Middleware>[];
  bool _globalHasMiddlewareReferences = false;

  EventManager? _cachedEventManager;
  bool _eventManagerChecked = false;

  final Map<String, String> _pathInternCache = {};

  /// Registry of configurable error handling hooks.
  final ErrorHandlingRegistry errorHooks;

  /// The HTTP server instance used to listen for incoming requests.
  HttpServer? _server;
  Http2ServerBinding? _http2Binding;

  /// A flag indicating whether the routes have been initialized.
  bool _routesInitialized = false;
  bool _providersBooted = false;
  final Map<String, List<Middleware>> _configuredMiddlewareGroups = {};
  final Set<Type> _registeredProviderTypes = {};

  /// The default router used when no other routers are explicitly mounted.
  final Router _defaultRouter = Router();
  bool _defaultRouterMounted = false;

  /// Tracks active requests by their unique ID.
  final Map<String, Request> _activeRequests = {};
  Completer<void>? _activeRequestsCompleter;

  /// Optional: Tracks the total number of requests handled by this engine.
  final int _totalRequests = 0;

  ShutdownController? _shutdownController;
  bool _draining = false;
  bool _ready = true;

  /// Returns the number of currently active requests.
  int get activeRequestCount => _activeRequests.length;

  /// Returns the total number of requests handled by this engine.
  int get totalRequests => _totalRequests;

  /// Whether the engine is accepting new requests.
  bool get isReady => !_draining && _ready;

  /// The port used by the active HTTP or HTTP/2 listener.
  int? get httpPort => _server?.port ?? _http2Binding?.port;

  /// Provides the shutdown controller for test inspection.
  @visibleForTesting
  ShutdownController? get shutdownController => _shutdownController;

  /// Attaches the native server used by the engine.
  @internal
  void attachServer(HttpServer server) {
    _server = server;
    _setupShutdownController();
  }

  /// The registered WebSocket routes exposed for diagnostics.
  Map<String, WebSocketEngineRoute> get debugWebSocketRoutes => _wsRoutes;

  /// Returns the registered WebSocket routes for test inspection.
  @visibleForTesting
  List<EngineRoute> get debugEngineRoutes => _engineRoutes;

  /// Returns the current path interning size for test inspection.
  @visibleForTesting
  int get debugPathInternCacheSize => _pathInternCache.length;

  /// Normalizes [path] for test inspection.
  @visibleForTesting
  String debugNormalizePath(String path) => _normalizePath(path);

  /// Returns whether event-manager initialization was checked.
  @visibleForTesting
  bool get debugEventManagerChecked => _eventManagerChecked;

  /// Stores WebSocket route handlers mapped by path.
  final Map<String, WebSocketEngineRoute> _wsRoutes = {};

  void _registerBareDefaults({EngineConfig? config}) {
    final engineConfig = config ?? EngineConfig();
    if (!container.has<EngineConfig>()) {
      container.instance<EngineConfig>(engineConfig);
    }
    if (!container.has<RoutePatternRegistry>()) {
      container.instance<RoutePatternRegistry>(RoutePatternRegistry.defaults());
    }
    if (!container.has<MiddlewareRegistry>()) {
      container.instance<MiddlewareRegistry>(MiddlewareRegistry());
    }
  }

  void _rebuildMiddlewareStacks() {
    if (!container.has<MiddlewareRegistry>()) {
      return;
    }
    _configuredMiddlewareGroups.clear();
    _markRoutesDirty();
  }

  /// Generates a URL for a named route with parameter substitution.
  ///
  /// Routes must be explicitly named using the `name()` method on [RouteBuilder]
  /// to be accessible through this method. All required route parameters must
  /// be provided in the [params] map.
  ///
  /// Example:
  /// ```dart
  /// engine.get('/users/{id}/posts/{postId}', handler).name('user.posts');
  ///
  /// final url = engine.route('user.posts', {
  ///   'id': 123,
  ///   'postId': 456,
  /// });
  /// // Returns: '/users/123/posts/456'
  /// ```
  ///
  /// Throws an [Exception] if a route with [name] is not found.
  /// Throws an [ArgumentError] if required parameters are missing or if
  /// unknown parameters are provided.
  String? route(String name, [Map<String, dynamic>? params]) {
    _ensureRoutes();

    final route = _routesByName[name];
    if (route == null) {
      throw Exception('Route with name "$name" not found');
    }

    // Collect placeholder names ( `:param`, `{param}`, `{param:int}`, `{param?}`, `{*param}` )
    final placeholderPattern = RegExp(r':(\w+)|{[*]?(\w+)[^}]*}');
    final placeholders = <String>{
      for (final m in placeholderPattern.allMatches(route.path))
        (m.group(1) ?? m.group(2))!,
    };

    params ??= const {};

    // Validate that every placeholder has a supplied value
    final missing = placeholders.where((p) => !params!.containsKey(p)).toList();
    if (missing.isNotEmpty) {
      throw ArgumentError(
        'Missing route parameter${missing.length == 1 ? "" : "s"}: '
        '${missing.join(", ")} for route "$name"',
      );
    }

    // Validate that no unknown params were provided
    final extra = params.keys.where((k) => !placeholders.contains(k)).toList();
    if (extra.isNotEmpty) {
      throw ArgumentError(
        'Unknown route parameter${extra.length == 1 ? "" : "s"}: '
        '${extra.join(", ")} for route "$name"',
      );
    }

    var path = route.path;

    // Perform replacement
    params.forEach((key, value) {
      path = path
          .replaceAll(':$key', value.toString())
          .replaceAll('{$key}', value.toString());
    });

    return path;
  }

  /// Mounts a router at a specific path prefix with optional middleware.
  ///
  /// This method allows organizing routes into separate router instances and
  /// mounting them at different path prefixes. Each mounted router can have
  /// its own engine-level middleware that applies to all routes within it.
  ///
  /// Example:
  /// ```dart
  /// final apiRouter = Router();
  /// apiRouter.get('/users', listUsers);
  /// apiRouter.get('/posts', listPosts);
  ///
  /// final adminRouter = Router();
  /// adminRouter.get('/dashboard', showDashboard);
  ///
  /// engine.use(apiRouter, prefix: '/api/v1', middlewares: [RateLimitMiddleware()]);
  /// engine.use(adminRouter, prefix: '/admin', middlewares: [AuthMiddleware()]);
  /// ```
  ///
  /// The [prefix] is prepended to all routes in the router. The [middlewares]
  /// are applied to all routes within this mount, executing before any
  /// route-specific middleware.
  Engine use(
    Router router, {
    String prefix = '',
    List<Middleware> middlewares = const [],
  }) {
    _markRoutesDirty();
    _mounts.add(_EngineMount(prefix, router, middlewares));
    return this;
  }

  /// Builds the final route table by flattening all mounted routers.
  ///
  /// This internal method processes all mounted routers and their routes to
  /// create a flat list of [EngineRoute] objects. For each route, it:
  /// 1. Merges the mount prefix with the route path
  /// 2. Combines engine-level middlewares with route-specific middlewares
  /// 3. Resolves middleware references using the middleware registry
  /// 4. Stores routes by name for URL generation
  ///
  /// This method is called automatically before serving requests and should
  /// not typically be called directly.
  void _build({String? parentGroupName}) {
    _ensureDefaultRouterMounted();
    _engineRoutes.clear();
    _routesByMethod.clear();
    _staticRoutesByMethod.clear();
    _fallbackRoutes.clear();
    _fallbackRoutesByMethod.clear();
    _routesByName = {};
    final patternRegistry = _resolveRoutePatterns();

    final registry = container.has<MiddlewareRegistry>()
        ? container.get<MiddlewareRegistry>()
        : null;
    _cachedGlobalMiddlewares = _resolveMiddlewares(middlewares, container);
    _globalHasMiddlewareReferences = _cachedGlobalMiddlewares.any(
      (middleware) => MiddlewareReference.lookup(middleware) != null,
    );

    for (final mount in _mounts) {
      // Let the child router finish its group & route merges
      mount.router.build(
        parentGroupName: parentGroupName,
        parentPrefix: mount.prefix,
      );

      var resolvedMountMiddlewares = mount.middlewares;
      if (registry != null) {
        mount.router.resolveMiddlewareReferences(registry, container);
        resolvedMountMiddlewares = registry.resolveAll(
          mount.middlewares,
          container,
        );
        mount.middlewares
          ..clear()
          ..addAll(resolvedMountMiddlewares);
      }

      // Flatten all routes
      final childRoutes = mount.router.getAllRoutes();
      for (final r in childRoutes) {
        // Combine the mount prefix with the route path
        final combinedPath = _joinPaths(mount.prefix, r.path);

        // Engine-level + route's final
        final allMiddlewares = [
          ...resolvedMountMiddlewares,
          ...r.finalMiddlewares,
        ];

        final engineRoute = EngineRoute(
          method: r.method,
          path: combinedPath,
          handler: (ctx) async {
            final v = await r.handler(ctx);
            return v is Response ? v : ctx.response;
          },
          patternRegistry: patternRegistry,
          name: r.name,
          middlewares: allMiddlewares,
          constraints: r.constraints,
          metadata: r.metadata,
          schema: r.schema,
          isFallback: r.constraints['isFallback'] == true,
          sourceFile: r.sourceFile,
          sourceLine: r.sourceLine,
          sourceColumn: r.sourceColumn,
        );

        // The engine is the first layer with visibility over the complete route
        // topology, including groups and mounted routers. Keep the first route
        // authoritative while surfacing later conflicts during development.
        final existingRoute = _engineRoutes.firstWhereOrNull(
          (route) =>
              route.method == engineRoute.method &&
              route.path == engineRoute.path,
        );
        if (existingRoute != null) {
          debugPrintWarning(
            'Duplicate route registered for [${engineRoute.method}] '
            '${engineRoute.path}. The later registration from '
            '${_routeSource(engineRoute)} was ignored; the first registration '
            'from ${_routeSource(existingRoute)} remains active.',
          );
          continue;
        }

        if (engineRoute.name != null) {
          if (_routesByName.containsKey(engineRoute.name)) {
            throw StateError('Duplicate route name "${engineRoute.name}"');
          }
          _routesByName[engineRoute.name!] = engineRoute;
        }

        _engineRoutes.add(engineRoute);
        if (engineRoute.isFallback) {
          _fallbackRoutes.add(engineRoute);
          _fallbackRoutesByMethod
              .putIfAbsent(engineRoute.method, () => <EngineRoute>[])
              .add(engineRoute);
        } else {
          _routesByMethod
              .putIfAbsent(engineRoute.method, () => <EngineRoute>[])
              .add(engineRoute);
          if (engineRoute.isStatic) {
            final methodRoutes = _staticRoutesByMethod.putIfAbsent(
              engineRoute.method,
              () => <String, EngineRoute>{},
            );
            methodRoutes[engineRoute.staticPath] = engineRoute;
          }
        }
        engineRoute.cacheHandlers(
          _cachedGlobalMiddlewares,
          cacheable: !_globalHasMiddlewareReferences,
        );
      }

      final childWebSockets = mount.router.getAllWebSocketRoutes();
      for (final ws in childWebSockets) {
        final combinedPath = _joinPaths(mount.prefix, ws.path);
        final allMiddlewares = [
          ...resolvedMountMiddlewares,
          ...ws.finalMiddlewares,
        ];
        final resolvedWsMiddlewares = _resolveMiddlewares(
          allMiddlewares,
          container,
        );
        final patternData = EngineRoute._buildUriPattern(
          combinedPath,
          patternRegistry,
        );

        _wsRoutes[combinedPath] = WebSocketEngineRoute(
          path: combinedPath,
          handler: ws.handler,
          pattern: patternData.pattern,
          paramInfo: patternData.paramInfo,
          middlewares: resolvedWsMiddlewares,
          patternRegistry: patternRegistry,
        );
      }
    }

    if (config.features.enableTrieRouting) {
      _trieByMethod.clear();
      for (final entry in _routesByMethod.entries) {
        _trieByMethod[entry.key] = RouteTrie.fromRoutes(entry.value);
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
    _ensureRoutes();
    for (final route in _engineRoutes) {
      print(route);
    }
  }

  /// Clears the built route cache so it can be rebuilt.
  void invalidateRoutes() {
    _markRoutesDirty();
  }

  void _markRoutesDirty() {
    _routesInitialized = false;
    _engineRoutes.clear();
    _routesByMethod.clear();
    _staticRoutesByMethod.clear();
    _trieByMethod.clear();
    _fallbackRoutes.clear();
    _fallbackRoutesByMethod.clear();
    _routesByName = {};
    _cachedGlobalMiddlewares = const <Middleware>[];
    _globalHasMiddlewareReferences = false;
  }

  RoutePatternRegistry _resolveRoutePatterns() {
    return requireRoutePatternRegistry(container);
  }

  List<Middleware> _resolveMiddlewares(
    Iterable<Middleware> source,
    Container container,
  ) {
    if (source.isEmpty) {
      return const <Middleware>[];
    }
    if (!container.has<MiddlewareRegistry>()) {
      return List<Middleware>.from(source);
    }
    final registry = container.get<MiddlewareRegistry>();
    return registry.resolveAll(source, container);
  }

  List<Middleware> _resolveGlobalMiddlewares(Container container) {
    if (!_globalHasMiddlewareReferences) {
      return _cachedGlobalMiddlewares;
    }
    if (!container.has<MiddlewareRegistry>()) {
      return _cachedGlobalMiddlewares;
    }
    final registry = container.get<MiddlewareRegistry>();
    return registry.resolveAll(middlewares, container);
  }

  List<Middleware> _resolveRouteMiddlewares(
    EngineRoute route,
    Container container,
  ) {
    if (!route.hasMiddlewareReference) {
      return route.middlewares;
    }
    if (!container.has<MiddlewareRegistry>()) {
      return route.middlewares;
    }
    final registry = container.get<MiddlewareRegistry>();
    return registry.resolveAll(route.middlewares, container);
  }

  Future<EventManager?> _resolveEventManager(Container container) async {
    final cached = _cachedEventManager;
    if (cached != null) {
      return cached;
    }
    if (_eventManagerChecked) {
      return null;
    }
    if (!container.has<EventManager>()) {
      _eventManagerChecked = true;
      return null;
    }
    final manager = await container.make<EventManager>();
    _cachedEventManager = manager;
    _eventManagerChecked = true;
    return manager;
  }

  String _normalizePath(String rawPath) {
    var normalized = rawPath.isEmpty ? '/' : rawPath;
    if (config.removeExtraSlash && normalized.contains('//')) {
      normalized = _collapseSlashes(normalized);
    }
    return _internPath(normalized);
  }

  String _collapseSlashes(String path) {
    final buffer = StringBuffer();
    var previousSlash = false;
    for (var i = 0; i < path.length; i++) {
      final char = path[i];
      if (char == '/') {
        if (previousSlash) {
          continue;
        }
        previousSlash = true;
      } else {
        previousSlash = false;
      }
      buffer.write(char);
    }
    final collapsed = buffer.toString();
    return collapsed.isEmpty ? '/' : collapsed;
  }

  String _internPath(String path) {
    final capacity = config.pathInternCacheSize;
    if (capacity <= 0) {
      return path;
    }
    final cached = _pathInternCache.remove(path);
    if (cached != null) {
      _pathInternCache[path] = cached;
      return cached;
    }
    _pathInternCache[path] = path;
    if (_pathInternCache.length > capacity) {
      _pathInternCache.remove(_pathInternCache.keys.first);
    }
    return path;
  }

  void _ensureDefaultRouterMounted() {
    if (_defaultRouterMounted) {
      return;
    }
    _mounts.add(_EngineMount('', _defaultRouter, const <Middleware>[]));
    _defaultRouterMounted = true;
  }

  /// Returns the set of HTTP methods that are valid for a given [path].
  ///
  /// Useful for building `Allow` headers (e.g. 405 responses, CORS pre-flight).
  /// Considers the trailing-slash alternative when
  /// [EngineConfig.redirectTrailingSlash] is enabled.
  Set<String> allowedMethods(String path) {
    _ensureRoutes();

    final normalizedPath = path.isEmpty ? '/' : path;
    final pathsToCheck = <String>{normalizedPath};
    if (config.redirectTrailingSlash) {
      final alt = normalizedPath.endsWith('/')
          ? normalizedPath.substring(0, normalizedPath.length - 1)
          : '$normalizedPath/';
      pathsToCheck.add(alt.isEmpty ? '/' : alt);
    }

    final methods = <String>{};
    for (final route in _engineRoutes) {
      if (route.isFallback) {
        continue;
      }

      final pattern = route._uriPattern;
      final matchesPath = pathsToCheck.any(
        (candidate) =>
            pattern.hasMatch(candidate) ||
            pattern.hasMatch(
              candidate.endsWith('/') ? candidate : '$candidate/',
            ),
      );
      if (!matchesPath) continue;
      methods.add(route.method);
    }
    return methods;
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
  Router get defaultRouter => _defaultRouter;

  void _onRequestStarted(Request request) {
    _activeRequests[request.id] = request;
    if (_activeRequestsCompleter == null ||
        _activeRequestsCompleter!.isCompleted) {
      _activeRequestsCompleter = Completer<void>();
    }
  }

  void _onRequestFinished(String id) {
    final removed = _activeRequests.remove(id);
    if (removed != null && _activeRequests.isEmpty) {
      _activeRequestsCompleter?.complete();
      _activeRequestsCompleter = null;
    }
  }

  /// Registers a WebSocket handler for the given path.
  ///
  /// The [path] parameter specifies the URL path at which the WebSocket handler will be mounted.
  /// The [handler] parameter is the [WebSocketHandler] instance that will handle WebSocket events.
  void ws(
    String path,
    WebSocketHandler handler, {
    List<Middleware> middlewares = const [],
  }) {
    _markRoutesDirty();
    final patternData = EngineRoute._buildUriPattern(
      path,
      _resolveRoutePatterns(),
    );
    final resolvedMiddlewares = _resolveMiddlewares(middlewares, container);
    _wsRoutes[path] = WebSocketEngineRoute(
      path: path,
      handler: handler,
      pattern: patternData.pattern,
      paramInfo: patternData.paramInfo,
      middlewares: resolvedMiddlewares,
      patternRegistry: _resolveRoutePatterns(),
    );
  }

  /// Handles an incoming host exchange via portable adapters.
  ///
  /// Prefer this entry from host transports (`routed_io`, `routed_node`,
  /// Workers, …).
  ///
  /// When [HttpConnection.request] implements [NativeRequestHandle] and
  /// [NativeRequestHandle.nativeRequest] is a `dart:io` [HttpRequest],
  /// dispatches directly to [handleRequest] (IO fast path: websockets,
  /// streaming, session). Otherwise runs the portable adapter pipeline
  /// ([_dispatchPortableConnection]).
  Future<void> handleConnection(HttpConnection connection) async {
    final request = connection.request;
    final upgrade = request is WebSocketUpgradeRequest
        ? request as WebSocketUpgradeRequest
        : null;
    if (upgrade?.isWebSocketUpgrade ?? false) {
      await _handlePortableWebSocket(connection, upgrade!);
      return;
    }
    if (request is NativeRequestHandle) {
      final native = (request as NativeRequestHandle).nativeRequest;
      if (native is HttpRequest) {
        return handleRequest(native);
      }
    }
    return _dispatchPortableConnection(connection);
  }

  Future<void> _handlePortableWebSocket(
    HttpConnection connection,
    WebSocketUpgradeRequest upgrade,
  ) async {
    if (!_providersBooted) await initialize();
    _ensureRoutes();
    final path = connection.request.uri.path;
    WebSocketEngineRoute? route;
    var pathParameters = const <String, dynamic>{};
    for (final candidate in _wsRoutes.values) {
      if (!candidate.pattern.hasMatch(path)) continue;
      route = candidate;
      pathParameters = candidate.extractParameters(path);
      break;
    }
    if (route == null) {
      connection.response.statusCode = HttpStatus.notFound;
      await connection.response.close();
      return;
    }

    final syntheticResponse = AdapterHttpResponse(connection.response);
    final syntheticRequest = AdapterHttpRequest(
      connection.request,
      syntheticResponse,
    );
    final request = Request(syntheticRequest, pathParameters, config);
    final response = Response.fromAdapter(connection.response);
    final container = createRequestContainer(
      syntheticRequest,
      syntheticResponse,
    );
    final context = EngineContext(
      request: request,
      response: response,
      engine: this,
      container: container,
    );
    _bindRequestScope(container, request, response, context);
    final socket = await upgrade.accept();
    final nativeResponse = upgrade.nativeUpgradeResponse;
    if (nativeResponse != null &&
        connection.response is WebSocketResponseAdapter) {
      (connection.response as WebSocketResponseAdapter).upgrade(nativeResponse);
    }
    final wsContext = WebSocketContext(socket, context);
    try {
      await route.handler.onOpen(wsContext);
      unawaited(
        _runPortableWebSocket(socket, route.handler, wsContext, container),
      );
    } catch (error, stackTrace) {
      await route.handler.onError(wsContext, error);
      await cleanupRequestContainer(container);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _runPortableWebSocket(
    RoutedWebSocket socket,
    WebSocketHandler handler,
    WebSocketContext context,
    Container container,
  ) async {
    try {
      await for (final message in socket.stream) {
        await handler.onMessage(context, message);
      }
      await handler.onClose(context);
    } catch (error) {
      await handler.onError(context, error);
    } finally {
      await cleanupRequestContainer(container);
    }
  }

  /// Value-style entry: [PortableRequest] in, [PortableResponse] out.
  ///
  /// Preferred for fetch-style hosts, tests, and hosts that buffer a full
  /// response. Does **not** use the IO [NativeRequestHandle] fast path.
  /// Pipeline still runs via [AdapterHttpBridge] until core is fully portable.
  Future<PortableResponse> handlePortable(PortableRequest request) async {
    final sink = RecordingResponseAdapter();
    await _dispatchPortableConnection(
      HttpConnection(request.asAdapter(), sink),
    );
    return sink.toPortableResponse();
  }

  /// Portable adapter path (no native `HttpRequest`). Transitional bridge.
  Future<void> _dispatchPortableConnection(HttpConnection connection) {
    final bridged = AdapterHttpBridge.toHttpRequest(connection);
    return handleRequest(bridged);
  }

  /// Handles an incoming HTTP request (`dart:io`).
  ///
  /// Prefer [handleConnection] from host adapters so non-`dart:io` hosts
  /// (e.g. Cloudflare Workers) can share the same engine entrypoint.
  ///
  /// This method is responsible for processing both HTTP and WebSocket upgrade requests.
  /// The actual implementation is in [ServerExtension._handleRequest].
  Future<void> handleRequest(HttpRequest httpRequest) async {
    if (_closed) {
      throw StateError('Cannot handle requests on a closed engine');
    }
    if (_draining || (_shutdownController?.isDraining ?? false)) {
      httpRequest.response.statusCode = HttpStatus.serviceUnavailable;
      httpRequest.response.headers.set(HttpHeaders.connectionHeader, 'close');
      await httpRequest.response.close();
      return;
    }
    if (!_providersBooted) await initialize();
    _ensureRoutes();
    Container? requestContainer;
    final rootContainer = container;
    final fastPathContainers = config.features.enableRequestContainerFastPath;
    final readOnlyRoot = fastPathContainers
        ? ReadOnlyContainer(rootContainer)
        : rootContainer;
    Container ensureRequestContainer() {
      if (fastPathContainers) {
        return readOnlyRoot;
      }
      return requestContainer ??= createRequestContainer(
        httpRequest,
        httpRequest.response,
      );
    }

    Request? trackedRequest;
    try {
      trackedRequest = await _handleRequest(
        httpRequest,
        rootContainer,
        ensureRequestContainer,
      );
    } finally {
      if (trackedRequest != null) {
        _onRequestFinished(trackedRequest.id);
      }
      if (requestContainer != null) {
        await cleanupRequestContainer(requestContainer!);
      }
    }
  }

  /// Close the engine and clean up resources
  Future<void> close() async {
    _closed = true;
    final server = _server;
    try {
      await server?.close(force: true);
    } catch (_) {}
    _server = null;
    final http2Binding = _http2Binding;
    if (http2Binding != null) {
      try {
        await http2Binding.close(force: true);
      } catch (_) {}
      _http2Binding = null;
    }
    final controller = _shutdownController;
    if (controller != null && !controller.isDraining) {
      controller.dispose();
      _shutdownController = null;
      container.remove<ShutdownController>();
    }
    _ready = false;
    await cleanupProviders();
    await container.cleanup();
  }

  /// Updates the engine's configuration.
  ///
  /// This method allows updating the configuration while maintaining immutability
  /// of the config object itself.
  void updateConfig(EngineConfig newConfig) {
    container.instance<EngineConfig>(newConfig);
    _rebuildMiddlewareStacks();
    _configureShutdownHooks();
  }

  void _configureShutdownHooks() {
    if (_shutdownController?.isDraining ?? false) {
      return;
    }
    _setupShutdownController();
  }

  void _setupShutdownController() {
    final server = _server;
    final shutdownConfig = config.shutdown;

    _shutdownController?.dispose();
    _shutdownController = null;
    container.remove<ShutdownController>();

    if (server == null || !shutdownConfig.enabled) {
      if (!shutdownConfig.enabled) {
        _ready = true;
      }
      return;
    }

    final controller = ShutdownController(
      config: shutdownConfig,
      onShutdown: () async {
        _draining = true;
        if (shutdownConfig.notifyReadiness) {
          _ready = false;
        }
        try {
          if (_http2Binding != null) {
            await _http2Binding!.close();
            _http2Binding = null;
            _server = null;
          } else {
            await server.close();
          }
        } catch (_) {}
      },
      onDrain: () async {
        await _waitForActiveRequests(Duration.zero);
        if (_activeRequests.isEmpty) {
          await close();
        }
      },
      onForceClose: () async {
        if (_http2Binding != null) {
          await _http2Binding!.close(force: true);
          _http2Binding = null;
          _server = null;
        }
        await _forceCloseActiveRequests(server);
      },
    );
    _shutdownController = controller;
    container.instance<ShutdownController>(controller);
    controller.watchSignals();
    controller.done.then((_) {
      _draining = false;
      _shutdownController = null;
      container.remove<ShutdownController>();
    });
  }

  Future<void> _waitForActiveRequests(Duration timeout) async {
    if (_activeRequests.isEmpty) {
      return;
    }
    _activeRequestsCompleter ??= Completer<void>();
    if (timeout <= Duration.zero) {
      await _activeRequestsCompleter!.future;
      return;
    }
    try {
      await _activeRequestsCompleter!.future.timeout(timeout);
    } on TimeoutException {
      // Timer in shutdown controller will handle forceful close.
    }
  }

  Future<void> _forceCloseActiveRequests(HttpServer? server) async {
    if (server != null) {
      try {
        await server.close(force: true);
      } catch (_) {}
      if (identical(_server, server)) {
        _server = null;
      }
    }
    for (final request in _activeRequests.values.toList()) {
      try {
        // Prefer closing through the tracked response when available; fall back
        // to native socket close for IO-only requests.
        if (request.hasNativeHttpRequest) {
          // The legacy accessor is required for the native response close path.
          // ignore: deprecated_member_use_from_same_package
          await request.httpRequest.response.close();
        }
      } catch (_) {}
    }
    _activeRequests.clear();
    _activeRequestsCompleter?.complete();
    _activeRequestsCompleter = null;
    await close();
  }

  /// Initialize the engine and boot service providers
  Future<void> initialize() async {
    container.instance<Engine>(this);
    await bootProviders();
    _warnUnresolvedProviderDependencies();
    _rebuildMiddlewareStacks();
    _cachedEventManager = await _resolveEventManager(container);
    _providersBooted = true;
  }

  void _warnUnresolvedProviderDependencies() {
    final unresolved = unresolvedProviderDependencies;
    if (unresolved.isEmpty) {
      return;
    }
    final details = unresolved.entries
        .map((entry) {
          final providerName = entry.key.runtimeType.toString();
          final deps = entry.value.map((type) => type.toString()).join(', ');
          return '$providerName -> [$deps]';
        })
        .join('; ');
    debugPrintWarning(
      'Unresolved provider dependencies during initialization: $details',
    );
  }

  /// Creates an initialized engine with all built-in providers.
  ///
  /// This is a convenience method that creates an engine with [builtins] and
  /// calls [initialize]. Use this for a fully-featured engine with all
  /// framework capabilities.
  ///
  /// Example:
  /// ```dart
  /// // Full-featured engine with all builtins
  /// final engine = await Engine.create();
  ///
  /// // With custom providers (overrides builtins default)
  /// final engine = await Engine.create(providers: Engine.defaultProviders);
  ///
  /// // Bare engine (no providers)
  /// final engine = await Engine.create(providers: []);
  ///
  static Future<Engine> create({
    EngineConfig? config,
    RuntimeContext? runtime,
    List<Middleware>? middlewares,
    List<EngineOpt>? options,
    ErrorHandlingRegistry? errorHandling,
    List<ServiceProvider>? providers,
  }) async {
    final engine = Engine(
      config: config,
      runtime: runtime,
      middlewares: middlewares,
      options: options,
      errorHandling: errorHandling,
      providers: providers ?? builtins,
    );
    await engine.initialize();
    return engine;
  }

  /// Adds [middleware] to the global middleware chain.
  void addGlobalMiddleware(Middleware middleware) {
    middlewares.add(middleware);
    _markRoutesDirty();
  }

  /// Returns a copy of the middleware group named [name].
  List<Middleware> middlewareGroup(String name) {
    final stack = _configuredMiddlewareGroups[name];
    if (stack == null) {
      return const [];
    }
    return List<Middleware>.from(stack);
  }

  /// Registers a typed error [handler].
  void onError<T extends Object>(EngineErrorHandler<T> handler) {
    errorHooks.addHandler(handler);
  }

  /// Registers an observer called before error handlers run.
  void beforeError(EngineErrorObserver observer) {
    errorHooks.addBefore(observer);
  }

  /// Registers an observer called after error handling completes.
  void afterError(EngineErrorObserver observer) {
    errorHooks.addAfter(observer);
  }
}

String _routeSource(EngineRoute route) {
  final file = route.sourceFile;
  if (file == null) {
    return 'an unknown source';
  }
  final line = route.sourceLine;
  final column = route.sourceColumn;
  if (line == null) {
    return file;
  }
  return column == null ? '$file:$line' : '$file:$line:$column';
}

/// Adds TLS serving to an [Engine].
extension SecureEngine on Engine {
  /// Serves the engine over TLS using the configured certificate and key.
  Future<void> serveSecure({
    String address = 'localhost',
    int port = 443,
    String? certificatePath,
    String? keyPath,
    String? certificatePassword,
    bool? v6Only,
    bool? requestClientCertificate,
    bool? shared,
  }) async {
    if (_engineRoutes.isEmpty) {
      _build();
    }
    if (config.features.enableProxySupport) {
      await config.parseTrustedProxies();
    }

    certificatePath ??= config.tlsCertificatePath;
    keyPath ??= config.tlsKeyPath;
    certificatePassword ??= config.tlsCertificatePassword;
    final effectiveV6Only = v6Only ?? config.tlsV6Only ?? false;
    final effectiveRequestClientCertificate =
        requestClientCertificate ?? config.tlsRequestClientCertificate ?? false;
    final effectiveShared = shared ?? config.tlsShared ?? false;

    if (certificatePath == null || keyPath == null) {
      throw ArgumentError(
        'TLS certificatePath and keyPath must be provided either via '
        'serveSecure parameters or configuration (http.tls.*).',
      );
    }

    final securityContext = SecurityContext()
      ..useCertificateChain(certificatePath, password: certificatePassword)
      ..usePrivateKey(keyPath, password: certificatePassword);

    if (config.http2.enabled) {
      final settings = config.http2.maxConcurrentStreams != null
          ? http2.ServerSettings(
              concurrentStreamLimit: config.http2.maxConcurrentStreams,
            )
          : const http2.ServerSettings();

      final binding = await Http2ServerBinding.bind(
        address: address,
        port: port,
        context: securityContext,
        settings: settings,
        v6Only: effectiveV6Only,
        requestClientCertificate: effectiveRequestClientCertificate,
        shared: effectiveShared,
      );

      _http2Binding = binding;
      _server = binding.http1Server;

      binding.start(
        handleHttp11: (request) async {
          await handleRequest(request);
        },
        handleHttp2: (stream, socket) async {
          await _handleHttp2Stream(stream, socket);
        },
        onError: (error, stackTrace) {
          stderr.writeln('HTTP/2 server error: $error\n$stackTrace');
        },
      );

      print(
        'Secure server listening on https://$address:${binding.port} (HTTP/2 enabled)',
      );
      _setupShutdownController();
      return;
    }

    securityContext.setAlpnProtocols(['http/1.1'], true);

    final server = await HttpServer.bindSecure(
      address,
      port,
      securityContext,
      v6Only: effectiveV6Only,
      requestClientCertificate: effectiveRequestClientCertificate,
      shared: effectiveShared,
    );

    _server = server;

    print('Secure server listening on https://$address:${server.port}');

    _setupShutdownController();

    await for (final request in server) {
      await handleRequest(request);
    }
  }

  Future<void> _handleHttp2Stream(
    http2.ServerTransportStream stream,
    Socket socket,
  ) async {
    try {
      final httpRequest = await Http2Adapter.createHttpRequest(stream, socket);
      await handleRequest(httpRequest);
    } catch (error, stackTrace) {
      stderr.writeln('HTTP/2 stream error: $error\n$stackTrace');
    }
  }
}
