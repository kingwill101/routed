import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:contextual/contextual.dart' as contextual;
import 'package:fuzzywuzzy/fuzzywuzzy.dart' as fuzzy;
import 'package:http2/http2.dart' as http2;
import 'package:meta/meta.dart' show internal, visibleForTesting;
import 'package:routed/middlewares.dart';
import 'package:routed/src/config/loader.dart';
import 'package:routed/src/config/registry.dart';
import 'package:routed/src/container/container.dart';
import 'package:routed/src/container/container_mixin.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/contracts/contracts.dart';
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/engine/engine_opt.dart';
import 'package:routed/src/engine/events/config.dart';
import 'package:routed/src/engine/events/request.dart';
import 'package:routed/src/engine/events/route.dart';
import 'package:routed/src/engine/http2_server.dart';
import 'package:routed/src/engine/middleware_registry.dart';
import 'package:routed/src/engine/provider_manifest.dart';
import 'package:routed/src/engine/providers/core.dart';
import 'package:routed/src/engine/providers/logging.dart';
import 'package:routed/src/engine/providers/registry.dart';
import 'package:routed/src/engine/providers/routing.dart';
import 'package:routed/src/engine/route_match.dart';
import 'package:routed/src/engine/wrapped_request.dart';
import 'package:routed/src/events/event_manager.dart';
import 'package:routed/src/logging/logging.dart';
import 'package:routed/src/observability/health.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/request.dart';
import 'package:routed/src/response.dart';
import 'package:routed/src/router/router.dart';
import 'package:routed/src/router/router_group_builder.dart';
import 'package:routed/src/router/types.dart';
import 'package:routed/src/runtime/shutdown.dart';
import 'package:routed/src/static_files.dart';
import 'package:routed/src/support/named_registry.dart';
import 'package:routed/src/utils/debug.dart';
import 'package:routed/src/validation/validator.dart';
import 'package:routed/src/websocket/websocket_handler.dart';

import '../support/zone.dart';

export 'events/events.dart';

part 'engine_route.dart';
part 'engine_routing.dart';
part 'error_handling.dart';
part 'mount.dart';
part 'param_utils.dart';
part 'patterns.dart';
part 'request.dart';

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
/// - **Configuration**: Comprehensive configuration system with YAML/JSON support
/// - **HTTP/2 Support**: Optional HTTP/2 protocol support with multiplexing
/// - **Graceful Shutdown**: Handle shutdown signals with configurable grace periods
///
/// ## Basic Usage
///
/// ```dart
/// final engine = Engine();
///
/// engine.get('/hello', (req) {
///   return Response.ok('Hello, World!');
/// });
///
/// engine.get('/users/:id', (req) {
///   final id = req.params['id'];
///   return Response.ok('User $id');
/// });
///
/// await engine.listen();
/// ```
///
/// ## With Configuration
///
/// ```dart
/// final engine = Engine(
///   config: EngineConfig(
///     security: EngineSecurityFeatures(
///       maxRequestSize: 10 * 1024 * 1024,
///       cors: CorsConfig(enabled: true),
///     ),
///   ),
///   options: [
///     withTrustedProxies(['192.168.1.1']),
///     withLogging(enabled: true, level: 'info'),
///   ],
/// );
/// ```
///
/// ## Mounting Routers
///
/// Multiple routers can be mounted at different path prefixes:
///
/// ```dart
/// final apiRouter = Router();
/// apiRouter.get('/users', listUsers);
///
/// engine.route('/api/v1', apiRouter, middlewares: [AuthMiddleware()]);
/// ```
///
/// ## Route Groups
///
/// Organize related routes with shared configuration:
///
/// ```dart
/// engine.group(
///   path: '/admin',
///   middlewares: [AuthMiddleware(), AdminMiddleware()],
///   builder: (router) {
///     router.get('/dashboard', showDashboard);
///     router.get('/users', listUsers);
///   },
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
///   void register() {
///     container.singleton<Database>((c) => Database());
///   }
///
///   @override
///   void boot() {
///     // Initialize database connection
///   }
/// }
///
/// final engine = Engine(providers: [DatabaseServiceProvider()]);
/// ```
class Engine with StaticFileHandler, ContainerMixin {
  bool _closed = false;

  /// The configuration settings for this engine.
  EngineConfig get config => container.get();

  /// The application configuration, providing access to application-level settings.
  Config get appConfig => container.get();

  /// A list of [_EngineMount] objects, representing the mounted routers and their prefixes.
  final List<_EngineMount> _mounts = [];

  /// A list of [EngineRoute] objects, representing the flattened route table.
  final List<EngineRoute> _engineRoutes = [];

  /// Map for quick lookup of routes by their name once the routing table is frozen.
  Map<String, EngineRoute> _routesByName = {};

  /// A list of global middlewares that are applied to all routes handled by this engine.
  List<Middleware> middlewares;

  /// Registry of configurable error handling hooks.
  final ErrorHandlingRegistry errorHooks;
  final ConfigLoaderOptions _configOptions;

  /// The HTTP server instance used to listen for incoming requests.
  HttpServer? _server;
  Http2ServerBinding? _http2Binding;

  /// A flag indicating whether the routes have been initialized.
  bool _routesInitialized = false;
  bool _providersBooted = false;
  bool _configLoadedEmitted = false;
  ProviderManifest? _providerManifest;
  final List<String> _unresolvedProviderIds = [];
  final bool _includeDefaultProviders;
  final Set<Middleware> _configuredGlobalSet = {};
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

  bool get isReady => !_draining && _ready;

  int? get httpPort => _server?.port ?? _http2Binding?.port;

  @visibleForTesting
  ShutdownController? get shutdownController => _shutdownController;

  @internal
  void attachServer(HttpServer server) {
    _server = server;
    _setupShutdownController();
  }

  @visibleForTesting
  Map<String, WebSocketEngineRoute> get debugWebSocketRoutes => _wsRoutes;

  /// Stores WebSocket route handlers mapped by path.
  final Map<String, WebSocketEngineRoute> _wsRoutes = {};

  /// Creates a new [Engine] instance with the given configuration.
  ///
  /// All parameters are optional and have sensible defaults for typical applications.
  ///
  /// The [config] parameter provides an [EngineConfig] object to customize
  /// core engine behavior including security, routing, and TLS settings.
  ///
  /// The [middlewares] parameter specifies global middleware applied to all
  /// routes. These execute before any route-specific middleware.
  ///
  /// The [options] parameter accepts a list of [EngineOpt] functions for
  /// additional configuration. These are applied in sequence after the main
  /// configuration.
  ///
  /// The [configItems] parameter provides a map of additional configuration
  /// values accessible via the [appConfig] property. Useful for storing
  /// application-specific settings.
  ///
  /// The [errorHandling] parameter allows customizing error handling behavior
  /// through an [ErrorHandlingRegistry]. If not provided, a default registry
  /// is used.
  ///
  /// The [configOptions] parameter controls how configuration files are loaded
  /// and processed from the filesystem.
  ///
  /// The [providers] parameter specifies custom service providers to register.
  /// These providers can register services, middleware, and perform initialization.
  ///
  /// The [includeDefaultProviders] parameter controls whether built-in service
  /// providers (core, routing, logging) are automatically registered. Default is `true`.
  ///
  /// Example:
  /// ```dart
  /// final engine = Engine(
  ///   config: EngineConfig(
  ///     security: EngineSecurityFeatures(maxRequestSize: 5 * 1024 * 1024),
  ///   ),
  ///   middlewares: [LoggingMiddleware()],
  ///   options: [
  ///     withCors(enabled: true),
  ///     withTrustedProxies(['10.0.0.0/8']),
  ///   ],
  ///   providers: [DatabaseServiceProvider()],
  /// );
  /// ```
  Engine({
    EngineConfig? config,
    List<Middleware>? middlewares,
    List<EngineOpt>? options,
    Map<String, dynamic>? configItems,
    ErrorHandlingRegistry? errorHandling,
    ConfigLoaderOptions? configOptions,
    List<ServiceProvider>? providers,
    bool includeDefaultProviders = true,
  }) : middlewares = middlewares ?? [],
       errorHooks = errorHandling?.clone() ?? ErrorHandlingRegistry(),
       _includeDefaultProviders = includeDefaultProviders,
       _configOptions = configOptions ?? const ConfigLoaderOptions() {
    if (includeDefaultProviders) {
      // Register built-in service providers first
      _registerBuiltInProviders(config: config, configItems: configItems);
    }

    if (providers != null && providers.isNotEmpty) {
      for (final provider in providers) {
        registerProvider(provider);
      }
    }
    // Apply options in order
    options?.forEach((opt) => opt(this));
    _loadManifestProviders();
    _rebuildMiddlewareStacks();
  }

  /// Registers the built-in service providers that come with the framework
  void _registerBuiltInProviders({
    EngineConfig? config,
    Map<String, dynamic>? configItems,
  }) {
    // Register core services
    final coreProvider = CoreServiceProvider(
      config: config,
      configItems: configItems,
      configOptions: _configOptions,
    );
    registerProvider(coreProvider);
    _registeredProviderTypes.add(coreProvider.runtimeType);

    // Register routing services
    final routingProvider = RoutingServiceProvider();
    registerProvider(routingProvider);
    _registeredProviderTypes.add(routingProvider.runtimeType);
  }

  void _loadManifestProviders() {
    if (!_includeDefaultProviders) {
      return;
    }
    if (_providerManifest != null) {
      return;
    }
    if (!container.has<Config>()) {
      return;
    }
    final config = container.get<Config>();
    final manifest = ProviderManifest.fromConfig(config);
    final registry = ProviderRegistry.instance;

    for (final id in manifest.providers) {
      final registration = registry.resolve(id);
      if (registration == null) {
        if (!_unresolvedProviderIds.contains(id)) {
          _unresolvedProviderIds.add(id);
        }
        continue;
      }
      final provider = registration.factory();
      if (_registeredProviderTypes.contains(provider.runtimeType)) {
        continue;
      }
      if (!_shouldActivateProvider(id, config)) {
        continue;
      }
      registerProvider(provider);
      _registeredProviderTypes.add(provider.runtimeType);
    }
    _providerManifest = manifest;
    _rebuildMiddlewareStacks();
    if (_unresolvedProviderIds.isNotEmpty) {
      debugPrintWarning(
        'Unknown providers in http.providers manifest: '
        '${_unresolvedProviderIds.join(', ')}',
      );
      _unresolvedProviderIds.clear();
    }
  }

  void _rebuildMiddlewareStacks() {
    if (!container.has<MiddlewareRegistry>() || !container.has<Config>()) {
      return;
    }
    final registry = container.get<MiddlewareRegistry>();
    final appConfig = container.get<Config>();
    final manifest = ProviderManifest.fromConfig(appConfig);

    final globalIds = <String>[];
    final groupIds = <String, List<String>>{};

    void appendUnique(List<String> target, Iterable<String> items) {
      for (final item in items) {
        if (!target.contains(item)) {
          target.add(item);
        }
      }
    }

    appendUnique(
      globalIds,
      appConfig.getStringListOrNull('http.middleware.global') ?? [],
    );
    final baseGroups = appConfig.getStringListMap('http.middleware.groups');
    groupIds.addAll(
      baseGroups,
    ); // shallow copy is fine as lists recreated below.

    final mergedSources = _collectMiddlewareSources(appConfig);

    for (final providerId in manifest.providers) {
      if (!_shouldActivateProvider(providerId, appConfig)) {
        continue;
      }
      final contribution = mergedSources[providerId];
      if (contribution == null) {
        continue;
      }
      appendUnique(globalIds, contribution.global);
      contribution.groups.forEach((group, ids) {
        final existing = groupIds.putIfAbsent(group, () => <String>[]);
        appendUnique(existing, ids);
      });
    }

    appConfig.set('http.middleware.global', List<String>.from(globalIds));
    appConfig.set(
      'http.middleware.groups',
      groupIds.map((key, ids) => MapEntry(key, List<String>.from(ids))),
    );

    final configuredGlobal = <Middleware>[];
    for (final id in globalIds) {
      final middleware = registry.build(id, container);
      if (middleware != null) {
        configuredGlobal.add(middleware);
      }
    }

    final userGlobal = middlewares
        .where((middleware) => !_configuredGlobalSet.contains(middleware))
        .toList();
    middlewares = [...configuredGlobal, ...userGlobal];
    _configuredGlobalSet
      ..clear()
      ..addAll(configuredGlobal);

    _configuredMiddlewareGroups.clear();
    groupIds.forEach((group, ids) {
      final stack = <Middleware>[];
      for (final id in ids) {
        final middleware = registry.build(id, container);
        if (middleware != null) {
          stack.add(middleware);
        }
      }
      _configuredMiddlewareGroups[group] = stack;
    });
  }

  Map<String, ProviderMiddlewareContribution> _collectMiddlewareSources(
    Config appConfig,
  ) {
    final contributions = <String, _MutableContribution>{};

    void merge(Object? raw) {
      if (raw is Map) {
        raw.forEach((key, value) {
          if (key is! String || value is! Map) {
            return;
          }
          final target = contributions.putIfAbsent(
            key,
            () => _MutableContribution(),
          );
          target.addGlobal(_stringList(value['global']));
          target.addGroups(
            parseStringListMap(
              value['groups'],
              context: 'middleware_sources.groups',
              throwOnInvalid: false,
            ),
          );
        });
      }
    }

    final registry = container.get<ConfigRegistry>();
    for (final entry in registry.entries) {
      final http = entry.defaults['http'];
      if (http is Map<String, dynamic>) {
        merge(http['middleware_sources']);
      }
    }

    merge(appConfig.get<Object?>('http.middleware_sources'));

    return contributions.map(
      (key, value) => MapEntry(key, value.toImmutable()),
    );
  }

  static List<String> _stringList(Object? value) {
    if (value is Iterable) {
      return value.map((e) => e.toString()).toList();
    }
    return const <String>[];
  }

  bool _shouldActivateProvider(String providerId, Config appConfig) {
    return true;
  }

  /// Creates a new engine instance from an existing engine.
  ///
  /// This factory creates a copy of [other], preserving its configuration,
  /// routes, middlewares, and error handling settings. Useful for creating
  /// variations of an engine with modified settings.
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
      configOptions: other._configOptions,
    );
    if (other.container.has<RoutePatternRegistry>()) {
      final registry = other.container.get<RoutePatternRegistry>();
      engine.container.instance<RoutePatternRegistry>(
        RoutePatternRegistry.clone(registry),
      );
    }
    if (other.container.has<ValidationRuleRegistry>()) {
      final registry = other.container.get<ValidationRuleRegistry>();
      engine.container.instance<ValidationRuleRegistry>(
        ValidationRuleRegistry.clone(registry),
      );
    }
    engine._mounts.addAll(other._mounts);
    engine._engineRoutes.addAll(other._engineRoutes);
    engine.middlewares.addAll(other.middlewares);
    return engine;
  }

  /// Creates a default engine instance with common production settings.
  ///
  /// This factory creates an engine with a 30-second timeout middleware
  /// pre-configured, which is suitable for most production applications.
  ///
  /// Example:
  /// ```dart
  /// final engine = Engine.d(
  ///   config: EngineConfig(
  ///     security: EngineSecurityFeatures(maxRequestSize: 10 * 1024 * 1024),
  ///   ),
  ///   options: [withCors(enabled: true)],
  /// );
  /// ```
  factory Engine.d({EngineConfig? config, List<EngineOpt>? options}) {
    return Engine(
      config: config ?? EngineConfig(),
      middlewares: [timeoutMiddleware(const Duration(seconds: 30))],
      options: options,
    );
  }

  /// Generates a URL for a named route with parameter substitution.
  ///
  /// Routes must be explicitly named using the `name()` method on [RouteBuilder]
  /// to be accessible through this method. All required route parameters must
  /// be provided in the [params] map.
  ///
  /// Example:
  /// ```dart
  /// engine.get('/users/:id/posts/:postId', handler).name('user.posts');
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
    _routesByName = {};
    final patternRegistry = _resolveRoutePatterns();

    final registry = container.has<MiddlewareRegistry>()
        ? container.get<MiddlewareRegistry>()
        : null;

    for (final mount in _mounts) {
      // Let the child router finish its group & route merges
      mount.router.build(
        parentGroupName: parentGroupName,
        parentPrefix: mount.prefix,
      );

      List<Middleware> resolvedMountMiddlewares = mount.middlewares;
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
          isFallback: r.constraints['isFallback'] == true,
        );

        // Uniqueness checks
        if (_engineRoutes.any(
          (er) =>
              er.method == engineRoute.method && er.path == engineRoute.path,
        )) {
          throw StateError(
            'Duplicate route registered for [${engineRoute.method}] ${engineRoute.path}',
          );
        }

        if (engineRoute.name != null) {
          if (_routesByName.containsKey(engineRoute.name)) {
            throw StateError('Duplicate route name "${engineRoute.name}"');
          }
          _routesByName[engineRoute.name!] = engineRoute;
        }

        _engineRoutes.add(engineRoute);
      }

      final childWebSockets = mount.router.getAllWebSocketRoutes();
      for (final ws in childWebSockets) {
        final combinedPath = _joinPaths(mount.prefix, ws.path);
        final allMiddlewares = [
          ...resolvedMountMiddlewares,
          ...ws.finalMiddlewares,
        ];
        final patternData = EngineRoute._buildUriPattern(
          combinedPath,
          patternRegistry,
        );

        _wsRoutes[combinedPath] = WebSocketEngineRoute(
          path: combinedPath,
          handler: ws.handler,
          pattern: patternData.pattern,
          paramInfo: patternData.paramInfo,
          middlewares: allMiddlewares,
          patternRegistry: patternRegistry,
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
    _routesByName = {};
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
    _wsRoutes[path] = WebSocketEngineRoute(
      path: path,
      handler: handler,
      pattern: patternData.pattern,
      paramInfo: patternData.paramInfo,
      middlewares: middlewares,
      patternRegistry: _resolveRoutePatterns(),
    );
  }

  /// Handles an incoming HTTP request.
  ///
  /// This method is responsible for processing both HTTP and WebSocket upgrade requests.
  /// The actual implementation is in [ServerExtension._handleRequest].
  Future<void> handleRequest(HttpRequest httpRequest) async {
    if (_closed) {
      throw StateError('Cannot handle requests on a closed engine');
    }
    final bypassHealth =
        container.has<HealthEndpointRegistry>() &&
        container.get<HealthEndpointRegistry>().allows(httpRequest.uri.path);

    if ((_draining || _shutdownController?.isDraining == true) &&
        !bypassHealth) {
      httpRequest.response.statusCode = HttpStatus.serviceUnavailable;
      httpRequest.response.headers.set(HttpHeaders.connectionHeader, 'close');
      await httpRequest.response.close();
      return;
    }
    if (!_providersBooted) await initialize();
    _ensureRoutes();
    final requestContainer = createRequestContainer(
      httpRequest,
      httpRequest.response,
    );
    Request? trackedRequest;
    try {
      trackedRequest = await _handleRequest(httpRequest, requestContainer);
    } finally {
      if (trackedRequest != null) {
        _onRequestFinished(trackedRequest.id);
      }
      await cleanupRequestContainer(requestContainer);
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
    if (_shutdownController?.isDraining == true) {
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
            await _http2Binding!.close(force: false);
            _http2Binding = null;
            _server = null;
          } else {
            await server.close(force: false);
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
        await request.httpRequest.response.close();
      } catch (_) {}
    }
    _activeRequests.clear();
    _activeRequestsCompleter?.complete();
    _activeRequestsCompleter = null;
    await close();
  }

  /// Replaces the current application configuration and notifies listeners.
  ///
  /// The [config] is bound into the root container, making it available for
  /// subsequent resolutions. A [ConfigReloadedEvent] is published so that
  /// interested listeners (e.g. caches, feature toggles) can react to the
  /// change. Optional [metadata] can describe the source of the reload.
  Future<void> replaceConfig(
    Config config, {
    Map<String, dynamic>? metadata,
  }) async {
    container.instance<Config>(config);
    await notifyProvidersOfConfigReload(config);
    _rebuildMiddlewareStacks();
    await _publishConfigEvent(ConfigReloadedEvent(config, metadata: metadata));
  }

  /// Initialize the engine and boot service providers
  Future<void> initialize() async {
    container.instance<Engine>(this);
    _loadManifestProviders();
    await bootProviders();
    _rebuildMiddlewareStacks();
    _providersBooted = true;
    await _emitConfigLoaded();
  }

  /// Creates an initialized engine.
  static Future<Engine> create({
    EngineConfig? config,
    List<Middleware>? middlewares,
    List<EngineOpt>? options,
    Map<String, dynamic>? configItems,
    ErrorHandlingRegistry? errorHandling,
    ConfigLoaderOptions? configOptions,
    List<ServiceProvider>? providers,
    bool includeDefaultProviders = true,
  }) async {
    final engine = Engine(
      config: config,
      middlewares: middlewares,
      options: options,
      configItems: configItems,
      errorHandling: errorHandling,
      configOptions: configOptions,
      providers: providers,
      includeDefaultProviders: includeDefaultProviders,
    );
    await engine.initialize();
    return engine;
  }

  void addGlobalMiddleware(Middleware middleware) {
    middlewares.add(middleware);
  }

  List<Middleware> middlewareGroup(String name) {
    final stack = _configuredMiddlewareGroups[name];
    if (stack == null) {
      return const [];
    }
    return List<Middleware>.from(stack);
  }

  void onError<T extends Object>(EngineErrorHandler<T> handler) {
    errorHooks.addHandler(handler);
  }

  void beforeError(EngineErrorObserver observer) {
    errorHooks.addBefore(observer);
  }

  void afterError(EngineErrorObserver observer) {
    errorHooks.addAfter(observer);
  }

  Future<void> _emitConfigLoaded() async {
    if (_configLoadedEmitted) {
      return;
    }
    if (!container.has<Config>()) {
      return;
    }
    _configLoadedEmitted = true;
    final config = container.get<Config>();
    await _publishConfigEvent(ConfigLoadedEvent(config));
  }

  Future<void> _publishConfigEvent(ConfigEvent event) async {
    if (!container.has<EventManager>()) {
      return;
    }
    final manager = await container.make<EventManager>();
    manager.publish(event);
  }
}

extension SecureEngine on Engine {
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
              concurrentStreamLimit: config.http2.maxConcurrentStreams!,
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
          LoggingContext.withValues({
            'event': 'engine_runtime_error',
            'scheme': 'https',
            'host': address,
            'port': binding.port,
            'http2': true,
            'error_type': error.runtimeType.toString(),
            'stack_trace': stackTrace.toString(),
          }, (logger) => logger.error('HTTP/2 server error: $error'));
          stderr.writeln('HTTP/2 server error: $error\n$stackTrace');
        },
      );

      await LoggingContext.withValues({
        'event': 'engine_started',
        'scheme': 'https',
        'host': address,
        'port': binding.port,
        'http2': true,
      }, (logger) => logger.info('Secure engine listening'));

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

    await LoggingContext.withValues({
      'event': 'engine_started',
      'scheme': 'https',
      'host': address,
      'port': server.port,
      'http2': false,
    }, (logger) => logger.info('Secure engine listening'));

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

class _MutableContribution {
  final Set<String> global = <String>{};
  final Map<String, Set<String>> groups = <String, Set<String>>{};

  void addGlobal(Iterable<String> items) {
    global.addAll(items);
  }

  void addGroups(Map<String, List<String>> items) {
    items.forEach((key, values) {
      final target = groups.putIfAbsent(key, () => <String>{});
      target.addAll(values);
    });
  }

  ProviderMiddlewareContribution toImmutable() {
    final mappedGroups = <String, List<String>>{};
    groups.forEach((key, value) {
      mappedGroups[key] = value.toList();
    });
    return ProviderMiddlewareContribution(
      global: global.toList(),
      groups: mappedGroups,
    );
  }
}
