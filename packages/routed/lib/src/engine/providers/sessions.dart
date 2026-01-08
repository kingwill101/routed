import 'package:routed/src/cache/cache_manager.dart';
import 'package:routed/src/config/spec.dart';
import 'package:routed/src/config/specs/session.dart';
import 'package:routed/src/config/specs/session_drivers.dart';
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/cache/repository.dart' as cache;
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/config.dart' show SessionConfig;
import 'package:routed/src/engine/middleware_registry.dart';
import 'package:routed/src/engine/storage_defaults.dart';
import 'package:routed/src/engine/storage_paths.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/sessions/cache_store.dart';
import 'package:routed/src/sessions/memory_store.dart';
import 'package:routed/src/sessions/middleware.dart';
import 'package:routed/src/sessions/options.dart';
import 'package:routed/src/sessions/secure_cookie.dart';
import 'package:routed/src/support/driver_registry.dart';

/// Signature for a function that converts a [SessionDriverBuilderContext] to a
/// fully-formed [SessionConfig] instance.
typedef SessionDriverBuilder =
    SessionConfig Function(SessionDriverBuilderContext context);

/// Signature for a callback that returns documentation describing a driver’s
/// configuration options.
///
/// The returned list is merged into the global configuration docs produced by
/// [SessionServiceProvider].
typedef SessionDriverDocBuilder =
    List<ConfigDocEntry> Function(SessionDriverDocContext context);

typedef SessionDriverValidator =
    void Function(SessionDriverBuilderContext context);

/// Context passed to a [SessionDriverBuilder].
///
/// The object aggregates every bit of information a driver might need to build
/// a concrete [SessionConfig].  Fields are intentionally kept immutable to
/// ensure the builder operates on a consistent snapshot of configuration.
class SessionDriverBuilderContext {
  SessionDriverBuilderContext({
    required this.container,
    required this.rootConfig,
    required this.raw,
    required this.driver,
    required this.cookieName,
    required this.lifetime,
    required this.expireOnClose,
    required this.encrypt,
    required this.options,
    required this.codecs,
    required this.cachePrefix,
    required this.keys,
    this.lottery,
    this.cacheManager,
    this.storageDefaults,
  });

  /// Application service container.
  final Container container;

  /// The root application configuration.
  final Config rootConfig;

  /// Parsed “session” map after normalisation/merging.
  final Map<String, dynamic> raw;

  /// Normalised driver identifier (e.g. “cookie”, “redis”).
  final String driver;

  /// Cookie name that will be sent back to the client.
  final String cookieName;

  /// Logical session lifetime.
  final Duration lifetime;

  /// Whether the session should be discarded when the browser closes.
  final bool expireOnClose;

  /// Whether the payload is encrypted when using cookie-based storage.
  final bool encrypt;

  /// Resolved cookie options.
  final Options options;

  /// Ordered list of [SecureCookie] codecs (primary first).
  final List<SecureCookie> codecs;

  /// Prefix applied to all cache keys for cache-backed drivers.
  final String cachePrefix;

  /// Application secret(s) used when signing/encrypting cookies.
  final List<String> keys;

  /// Odds used by _file_ drivers to trigger garbage collection.
  final List<int>? lottery;

  /// Lazily-injected cache manager (may be `null` for non cache drivers).
  final CacheManager? cacheManager;

  /// Storage defaults reported by the storage provider.
  final StorageDefaults? storageDefaults;

  /// Returns the cache [cache.Repository] identified by [name] or throws
  /// [ProviderConfigException] if the cache manager is absent.
  cache.Repository requireCacheStore(String name) {
    final manager = cacheManager;
    if (manager == null) {
      throw ProviderConfigException(
        'Cache manager is required for cache-backed session drivers.',
      );
    }
    return manager.store(name);
  }
}

/// Context object supplied to a [SessionDriverDocBuilder].
///
/// It mainly exists to help the builder derive fully-qualified configuration
/// paths.
class SessionDriverDocContext {
  SessionDriverDocContext({required this.driver, required this.pathBase});

  /// Normalised driver identifier being documented.
  final String driver;

  /// Root configuration path (e.g. “session”).
  final String pathBase;

  /// Produces a full configuration path by appending [segment] to
  /// [pathBase] using a dot separator.
  String path(String segment) => '$pathBase.$segment';
}

/// Registry responsible for managing session driver registrations.
///
/// Third-party packages can use [register] and [unregister] to expose their own
/// drivers at runtime.  The class is a thin singleton wrapper around a map,
/// deliberately avoiding any global state beyond the registry itself.
class SessionDriverRegistry
    extends
        DriverRegistryBase<
          SessionDriverBuilder,
          SessionDriverDocContext,
          SessionDriverValidator,
          SessionDriverRegistration
        > {
  SessionDriverRegistry._internal();

  /// Singleton accessor.
  static final SessionDriverRegistry instance =
      SessionDriverRegistry._internal();

  @override
  SessionDriverRegistration createRegistration(
    SessionDriverBuilder builder, {
    DriverDocBuilder<SessionDriverDocContext>? documentation,
    SessionDriverValidator? validator,
    List<String> requiresConfig = const [],
  }) {
    return SessionDriverRegistration(
      builder: builder,
      documentation: documentation,
      validator: validator,
      requiresConfig: requiresConfig,
    );
  }

  @override
  SessionDriverDocContext buildDocContext(
    String driver, {
    required String pathBase,
  }) {
    return SessionDriverDocContext(driver: driver, pathBase: pathBase);
  }

  /// Registers a new session [driver].
  ///
  /// Supplying [documentation] allows the driver to contribute to
  /// configuration documentation.  When [overrideExisting] is `false`,
  /// an existing registration with the same name will be left untouched.
  void register(
    String driver,
    SessionDriverBuilder builder, {
    SessionDriverDocBuilder? documentation,
    bool overrideExisting = true,
    SessionDriverValidator? validator,
    List<String> requiresConfig = const [],
  }) {
    registerDriver(
      driver,
      builder,
      documentation: documentation,
      validator: validator,
      requiresConfig: requiresConfig,
      overrideExisting: overrideExisting,
    );
  }

  /// Removes the registration associated with [driver] if it exists.
  void unregister(String driver) => unregisterEntry(driver);

  /// Returns `true` if a registration exists for [driver].
  bool contains(String driver) => containsEntry(driver);

  /// Retrieves the builder associated with [driver] or `null` when absent.
  SessionDriverBuilder? builderFor(String driver) =>
      registrationFor(driver)?.builder;

  void ensureRequirements(
    String driver,
    SessionDriverBuilderContext context,
    SessionDriverRegistration registration,
  ) {
    for (final key in registration.requiresConfig) {
      final value = context.raw[key];
      if (value == null) {
        throw ProviderConfigException(
          'Session driver "$driver" requires configuration key "$key".',
        );
      }
      if (value is String && value.trim().isEmpty) {
        throw ProviderConfigException(
          'Session driver "$driver" requires configuration key "$key" to be non-empty.',
        );
      }
    }
  }

  void runValidator(
    String driver,
    SessionDriverBuilderContext context,
    SessionDriverRegistration registration,
  ) {
    final validator = registration.validator;
    if (validator == null) {
      return;
    }
    try {
      validator(context);
    } on ProviderConfigException {
      rethrow;
    } catch (error) {
      throw ProviderConfigException(
        'Session driver "$driver" validation failed: $error',
      );
    }
  }

  /// Returns a sorted list of available driver names, ensuring that [include]
  /// is always present in the result.
  List<String> availableDrivers({Iterable<String> include = const []}) =>
      driverNames(include: include).toList(growable: false);

  /// Collates documentation from all registered drivers.
  @override
  List<ConfigDocEntry> documentation({required String pathBase}) =>
      super.documentation(pathBase: pathBase);

  @override
  bool onDuplicate(
    String name,
    SessionDriverRegistration existing,
    bool overrideExisting,
  ) {
    if (!overrideExisting) {
      return false;
    }
    throw ProviderConfigException(
      'Session driver "$name" is already registered.'
      '${duplicateDiagnostics(name)}',
    );
  }
}

class SessionDriverRegistration
    extends
        DriverRegistration<
          SessionDriverBuilder,
          SessionDriverDocContext,
          SessionDriverValidator
        > {
  SessionDriverRegistration({
    required super.builder,
    super.documentation,
    super.validator,
    super.requiresConfig,
  });
}

/// Service provider that wires all session-related services and publishes
/// default configuration.
///
/// The provider also exposes a lightweight plugin system allowing packages to
/// add new session drivers at runtime.
class SessionServiceProvider extends ServiceProvider
    with ProvidesDefaultConfig {
  static const List<String> _builtInDrivers = <String>[
    'cookie',
    'file',
    'array',
    'redis',
    'cache',
  ];

  static bool _defaultsRegistered = false;
  bool _managesConfig = false;
  static const SessionConfigSpec spec = SessionConfigSpec();
  static const SessionCookieDriverSpec _cookieSpec = SessionCookieDriverSpec();
  static const SessionFileDriverSpec _fileSpec = SessionFileDriverSpec();
  static const SessionArrayDriverSpec _arraySpec = SessionArrayDriverSpec();
  static const SessionCacheDriverSpec _cacheSpec = SessionCacheDriverSpec();

  /// Default configuration as understood by the framework.
  @override
  ConfigDefaults get defaultConfig {
    final values = spec.defaultsWithRoot();
    values['http'] = {
      'middleware_sources': {
        'routed.sessions': {
          'global': ['routed.sessions.start'],
          'groups': {
            'web': ['routed.sessions.start'],
          },
        },
      },
    };
    return ConfigDefaults(
      docs: <ConfigDocEntry>[
        ...spec.docs().map((entry) {
          if (entry.path == 'session.driver') {
            return ConfigDocEntry(
              path: entry.path,
              type: entry.type,
              description: entry.description,
              example: entry.example,
              deprecated: entry.deprecated,
              optionsBuilder: () => SessionServiceProvider.availableDriverNames(
                includeBuiltIns: true,
              ),
              metadata: entry.metadata,
              defaultValue: entry.defaultValue,
              defaultValueBuilder: entry.defaultValueBuilder,
            );
          }
          return entry;
        }),
        ...SessionServiceProvider.driverDocumentation(),
        const ConfigDocEntry(
          path: 'http.middleware_sources',
          type: 'map',
          description:
              'Session middleware references injected globally/groups.',
          defaultValue: <String, Object?>{
            'routed.sessions': <String, Object?>{
              'global': <String>['routed.sessions.start'],
              'groups': <String, Object?>{
                'web': <String>['routed.sessions.start'],
              },
            },
          },
        ),
      ],
      values: values,
      schemas: spec.schemaWithRoot(),
    );
  }

  /// Returns a list of registered driver names, with optional built-ins.
  static List<String> availableDriverNames({bool includeBuiltIns = false}) {
    _ensureDefaultDriversRegistered();
    final include = includeBuiltIns ? _builtInDrivers : const <String>[];
    return SessionDriverRegistry.instance
        .availableDrivers(include: include)
        .toList();
  }

  /// Collects documentation for every registered driver.
  static List<ConfigDocEntry> driverDocumentation() {
    _ensureDefaultDriversRegistered();
    return SessionDriverRegistry.instance.documentation(pathBase: 'session');
  }

  /// Ensures that built-in drivers are registered once and only once.
  static void _ensureDefaultDriversRegistered() {
    if (_defaultsRegistered) {
      return;
    }
    registerDriver(
      'cookie',
      _buildCookieDriver,
      documentation: _cookieDriverDocs,
      overrideExisting: false,
    );
    registerDriver(
      'file',
      _buildFileDriver,
      documentation: _fileDriverDocs,
      overrideExisting: false,
    );
    registerDriver(
      'array',
      _buildArrayDriver,
      documentation: _arrayDriverDocs,
      overrideExisting: false,
    );
    for (final driver in const ['redis', 'cache']) {
      registerDriver(
        driver,
        _buildCacheBackedDriver,
        documentation: _cacheBackedDriverDocs,
        overrideExisting: false,
        validator: _validateCacheBackedDriver,
      );
    }
    _defaultsRegistered = true;
  }

  // ---------------------------------------------------------------------------
  // Driver builders
  // ---------------------------------------------------------------------------

  static SessionConfig _buildCookieDriver(SessionDriverBuilderContext context) {
    return SessionConfig.cookie(
      codecs: context.codecs,
      cookieName: context.cookieName,
      maxAge: context.lifetime,
      expireOnClose: context.expireOnClose,
      options: context.options,
    );
  }

  static SessionConfig _buildFileDriver(SessionDriverBuilderContext context) {
    final specContext = SessionDriverSpecContext(
      driver: context.driver,
      pathBase: 'session',
      config: context.rootConfig,
    );
    final resolved = _fileSpec.fromMap(context.raw, context: specContext);
    final configuredPath = resolved.storagePath;

    final storageDefaults = context.storageDefaults;
    final storagePath = () {
      if (configuredPath != null && configuredPath.trim().isNotEmpty) {
        final trimmed = configuredPath.trim();
        if (storageDefaults != null) {
          return storageDefaults.resolve(trimmed);
        }
        return normalizeStoragePath(context.rootConfig, trimmed);
      }
      if (storageDefaults != null) {
        return storageDefaults.frameworkPath('sessions');
      }
      return resolveFrameworkStoragePath(context.rootConfig, child: 'sessions');
    }();

    return SessionConfig.file(
      appKey: context.keys.first,
      codecs: context.codecs,
      storagePath: storagePath,
      cookieName: context.cookieName,
      maxAge: context.lifetime,
      expireOnClose: context.expireOnClose,
      options: context.options,
      lottery: resolved.lottery ?? context.lottery,
    );
  }

  static SessionConfig _buildArrayDriver(SessionDriverBuilderContext context) {
    final store = MemorySessionStore(
      codecs: context.codecs,
      defaultOptions: context.options,
      lifetime: context.lifetime,
    );

    return SessionConfig(
      cookieName: context.cookieName,
      store: store,
      maxAge: context.lifetime,
      path: context.options.path ?? '/',
      secure: context.options.secure ?? false,
      httpOnly: context.options.httpOnly ?? true,
      defaultOptions: context.options,
      expireOnClose: context.expireOnClose,
      sameSite: context.options.sameSite,
      partitioned: context.options.partitioned,
      codecs: context.codecs,
    );
  }

  static SessionConfig _buildCacheBackedDriver(
    SessionDriverBuilderContext context,
  ) {
    final cacheManager = context.cacheManager;
    if (cacheManager == null) {
      throw ProviderConfigException(
        'Cache manager is required for cache-backed session drivers.',
      );
    }

    final specContext = SessionDriverSpecContext(
      driver: context.driver,
      pathBase: 'session',
      config: context.rootConfig,
    );
    final resolved = _cacheSpec.fromMap(context.raw, context: specContext);
    final storeName = resolved.resolveStoreName(context.driver);
    final repository = cacheManager.store(storeName);

    final store = CacheSessionStore(
      repository: repository,
      codecs: context.codecs,
      defaultOptions: context.options,
      cachePrefix: context.cachePrefix,
      lifetime: context.lifetime,
    );

    return SessionConfig(
      cookieName: context.cookieName,
      store: store,
      maxAge: context.lifetime,
      path: context.options.path ?? '/',
      secure: context.options.secure ?? false,
      httpOnly: context.options.httpOnly ?? true,
      defaultOptions: context.options,
      expireOnClose: context.expireOnClose,
      sameSite: context.options.sameSite,
      partitioned: context.options.partitioned,
      codecs: context.codecs,
    );
  }

  static void _validateCacheBackedDriver(SessionDriverBuilderContext context) {
    final cacheManager = context.cacheManager;
    if (cacheManager == null) {
      throw ProviderConfigException(
        'Cache manager is required for cache-backed session drivers.',
      );
    }
    final specContext = SessionDriverSpecContext(
      driver: context.driver,
      pathBase: 'session',
      config: context.rootConfig,
    );
    final resolved = _cacheSpec.fromMap(context.raw, context: specContext);
    final storeName = resolved.resolveStoreName(context.driver);
    if (!cacheManager.hasStore(storeName)) {
      final available = cacheManager.storeNames;
      final hint = available.isEmpty
          ? 'No cache stores are configured.'
          : 'Available stores: ${available.join(", ")}';
      throw ProviderConfigException(
        'Session cache store [$storeName] is not defined. $hint',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Driver documentation helpers
  // ---------------------------------------------------------------------------

  static List<ConfigDocEntry> _cookieDriverDocs(
    SessionDriverDocContext context,
  ) {
    return _cookieSpec.docs(pathBase: context.pathBase);
  }

  static List<ConfigDocEntry> _fileDriverDocs(SessionDriverDocContext context) {
    return _fileSpec.docs(pathBase: context.pathBase);
  }

  static List<ConfigDocEntry> _arrayDriverDocs(
    SessionDriverDocContext context,
  ) => _arraySpec.docs(pathBase: context.pathBase);

  static List<ConfigDocEntry> _cacheBackedDriverDocs(
    SessionDriverDocContext context,
  ) {
    return _cacheSpec.docs(pathBase: context.pathBase);
  }

  /// Convenience wrapper around [SessionDriverRegistry.register].
  static void registerDriver(
    String driver,
    SessionDriverBuilder builder, {
    SessionDriverDocBuilder? documentation,
    bool overrideExisting = true,
    SessionDriverValidator? validator,
    List<String> requiresConfig = const [],
  }) {
    SessionDriverRegistry.instance.register(
      driver,
      builder,
      documentation: documentation,
      overrideExisting: overrideExisting,
      validator: validator,
      requiresConfig: requiresConfig,
    );
  }

  /// Convenience wrapper around [SessionDriverRegistry.unregister].
  static void unregisterDriver(String driver) {
    SessionDriverRegistry.instance.unregister(driver);
  }

  // ---------------------------------------------------------------------------
  // ServiceProvider overrides
  // ---------------------------------------------------------------------------

  @override
  void register(Container container) {
    final appConfig = container.get<Config>();
    final resolved = _resolveSessionConfig(container, appConfig);
    if (resolved != null) {
      container.instance<SessionConfig>(resolved);
      _managesConfig = true;
    } else {
      _managesConfig = false;
    }

    final registry = container.get<MiddlewareRegistry>();
    registry.register('routed.sessions.start', (c) {
      SessionConfig? config;
      if (c.has<SessionConfig>()) {
        config = c.get<SessionConfig>();
      } else {
        config = _resolveSessionConfig(c, c.get<Config>());
        if (config != null) {
          c.instance<SessionConfig>(config);
        }
      }

      if (config == null) {
        return (ctx, next) async => await next();
      }
      return sessionMiddleware(store: config.store, name: config.cookieName);
    });
  }

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    final resolved = _resolveSessionConfig(container, config);
    if (resolved == null) {
      if (_managesConfig) {
        container.remove<SessionConfig>();
        _managesConfig = false;
      }
      return;
    }

    container.instance<SessionConfig>(resolved);
    _managesConfig = true;
  }

  // ---------------------------------------------------------------------------
  // Configuration helpers
  // ---------------------------------------------------------------------------

  SessionConfig? _resolveSessionConfig(Container container, Config config) {
    final direct = config.get<Object?>('session.config');
    if (direct is SessionConfig) {
      return direct;
    }
    if (direct is Map || direct is Config) {
      final resolved = _resolveSessionProviderConfigFromMap(direct, config);
      if (!resolved.enabled) {
        return null;
      }
      return _buildSessionConfig(container, config, resolved);
    }

    final sessionNode = config.get<Object?>('session');
    if (sessionNode is SessionConfig) {
      return sessionNode;
    } else if (sessionNode is Map) {
      // handled via spec.resolve below
    } else if (sessionNode is Config) {
      // handled via spec.resolve below
    } else if (sessionNode != null) {
      throw ProviderConfigException('session must be a map');
    }

    final resolved = spec.resolve(config);
    if (!resolved.enabled) {
      return null;
    }
    return _buildSessionConfig(container, config, resolved);
  }

  SessionConfig _buildSessionConfig(
    Container container,
    Config root,
    SessionProviderConfig resolved,
  ) {
    _ensureDefaultDriversRegistered();
    final registry = SessionDriverRegistry.instance;
    final context = SessionDriverBuilderContext(
      container: container,
      rootConfig: root,
      raw: resolved.raw,
      driver: resolved.driver,
      cookieName: resolved.cookieName,
      lifetime: resolved.lifetime,
      expireOnClose: resolved.expireOnClose,
      encrypt: resolved.encrypt,
      options: resolved.options,
      codecs: resolved.codecs,
      cachePrefix: resolved.cachePrefix,
      keys: resolved.keys,
      lottery: resolved.lottery,
      cacheManager: container.has<CacheManager>()
          ? container.get<CacheManager>()
          : null,
      storageDefaults: container.has<StorageDefaults>()
          ? container.get<StorageDefaults>()
          : null,
    );

    final registration = registry.registrationFor(resolved.driver);
    if (registration == null) {
      final available =
          registry.availableDrivers(include: _builtInDrivers).toList()..sort();
      final message = available.isEmpty
          ? 'No session drivers are registered.'
          : 'Registered drivers: ${available.join(", ")}.';
      throw ProviderConfigException(
        'Unsupported session driver "${resolved.driver}". $message',
      );
    }
    final builder = registration.builder;
    registry.ensureRequirements(resolved.driver, context, registration);
    registry.runValidator(resolved.driver, context, registration);
    return builder(context);
  }

  SessionProviderConfig _resolveSessionProviderConfigFromMap(
    Object? raw,
    Config root,
  ) {
    final map = stringKeyedMap(raw as Object, 'session.config');
    final specContext = ConfigSpecContext(config: root);
    final merged = spec.mergeDefaults(map, context: specContext);
    return spec.fromMap(merged, context: specContext);
  }
}
