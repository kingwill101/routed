import 'package:routed/src/cache/array_store_factory.dart';
import 'package:routed/src/cache/file_store_factory.dart';
import 'package:routed/src/cache/null_store_factory.dart';
import 'package:routed/src/cache/redis_store_factory.dart';
import 'package:routed/src/cache/repository.dart';
import 'package:routed/src/cache/store_factory.dart';
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/cache/repository.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/storage_defaults.dart';
import 'package:routed/src/engine/storage_paths.dart';
import 'package:routed/src/events/event_manager.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/support/driver_registry.dart';

/// A builder function that creates a [StoreFactory] instance.
///
/// This is used by the [CacheDriverRegistry] to lazily construct store factories
/// for registered cache drivers.
typedef StoreFactoryBuilder = StoreFactory Function();

/// A builder function that generates configuration documentation entries for a cache driver.
///
/// The [CacheDriverDocContext] provides context such as the driver name and
/// base path for generating configuration keys.
typedef CacheDriverDocBuilder =
    List<ConfigDocEntry> Function(CacheDriverDocContext context);

/// Context provided to cache driver documentation builders.
///
/// This context helps in constructing full configuration paths and
/// identifying the driver being documented.
class CacheDriverDocContext {
  /// Creates a new [CacheDriverDocContext].
  ///
  /// The [driver] is the identifier for the cache driver (e.g., 'file', 'redis').
  /// The [pathBase] is the root configuration path for this driver, typically
  /// `cache.stores.<driver_name>`.
  CacheDriverDocContext({required this.driver, required this.pathBase});

  /// The name of the cache driver being documented.
  final String driver;

  /// The base configuration path for this driver (e.g., 'cache.stores.file').
  final String pathBase;

  /// Builds a full configuration path for a given [segment].
  ///
  /// Combines the [pathBase] with the [segment] using dot notation.
  ///
  /// ```dart
  /// final context = CacheDriverDocContext(driver: 'file', pathBase: 'cache.stores.file');
  /// print(context.path('path')); // 'cache.stores.file.path'
  /// ```
  String path(String segment) => '$pathBase.$segment';
}

/// Context provided to cache driver configuration builders.
class DriverConfigContext {
  /// Creates a new [DriverConfigContext].
  DriverConfigContext({
    required this.userConfig,
    required this.container,
    required this.driverName,
  });

  /// The original configuration supplied by the user or provider.
  ///
  /// This map is unmodifiable.
  final Map<String, dynamic> userConfig;

  /// The application's service [Container] for looking up dependencies.
  final Container container;

  /// The normalized identifier for the cache driver.
  final String driverName;

  /// Attempts to synchronously resolve a service of type [T] from the [container].
  ///
  /// Returns `null` if the service is not available, cannot be resolved
  /// synchronously, or if any error occurs during resolution.
  ///
  /// ```dart
  /// // Inside a DriverConfigBuilder:
  /// final StorageDefaults? defaults = context.get<StorageDefaults>();
  /// if (defaults != null) {
  ///   // Use storage defaults
  /// }
  /// ```
  T? get<T>() {
    if (!container.has<T>()) {
      return null;
    }
    try {
      return container.get<T>();
    } catch (_) {
      return null;
    }
  }
}

/// A builder that constructs the final configuration for a cache driver.
///
/// This function is invoked by the [CacheDriverRegistry] to process and
/// augment the user-provided configuration before it's used to create a store.
typedef DriverConfigBuilder =
    Map<String, dynamic> Function(DriverConfigContext context);

/// A validator invoked after a cache driver's configuration has been built.
///
/// This function allows for custom validation logic and should throw a
/// [ConfigurationException] if the configuration is invalid.
typedef DriverConfigValidator =
    void Function(Map<String, dynamic> config, String driverName);

/// Exception raised when cache driver configuration is invalid.
class ConfigurationException implements Exception {
  /// Creates a new [ConfigurationException] with the given [message].
  const ConfigurationException(this.message);

  /// The detailed error message describing the configuration issue.
  final String message;

  @override
  String toString() => 'ConfigurationException: $message';
}

/// A registration entry for a cache driver.
///
/// Extends [DriverRegistration] to include a [configBuilder] specific to
/// cache drivers, allowing custom configuration processing.
class CacheDriverRegistration
    extends
        DriverRegistration<
          StoreFactoryBuilder,
          CacheDriverDocContext,
          DriverConfigValidator
        > {
  /// Creates a [CacheDriverRegistration].
  CacheDriverRegistration({
    required super.builder,
    super.documentation,
    super.validator,
    super.requiresConfig,
    this.configBuilder,
  });

  /// An optional builder that constructs the final configuration for this driver.
  final DriverConfigBuilder? configBuilder;
}

/// A registry for managing cache drivers.
///
/// This singleton class allows for registering, unregistering, and retrieving
/// cache driver builders and their associated metadata. It also handles the
/// building and validation of driver configurations.
///
/// Built-in drivers (`array`, `file`, `null`, `redis`) are automatically
/// registered upon first access.
class CacheDriverRegistry
    extends
        DriverRegistryBase<
          StoreFactoryBuilder,
          CacheDriverDocContext,
          DriverConfigValidator,
          CacheDriverRegistration
        > {
  /// Creates an internal instance of [CacheDriverRegistry].
  CacheDriverRegistry._internal();

  /// The singleton instance of the [CacheDriverRegistry].
  static final CacheDriverRegistry instance = CacheDriverRegistry._internal();

  @override
  CacheDriverRegistration createRegistration(
    StoreFactoryBuilder builder, {
    DriverDocBuilder<CacheDriverDocContext>? documentation,
    DriverConfigValidator? validator,
    List<String> requiresConfig = const [],
  }) {
    return CacheDriverRegistration(
      builder: builder,
      documentation: documentation,
      validator: validator,
      requiresConfig: requiresConfig,
    );
  }

  @override
  CacheDriverDocContext buildDocContext(
    String driver, {
    required String pathBase,
  }) {
    return CacheDriverDocContext(driver: driver, pathBase: pathBase);
  }

  /// Registers a cache driver with the registry.
  ///
  /// The [driver] is a unique identifier for the cache type (e.g., 'file', 'redis').
  /// The [builder] is a function that produces a [StoreFactory] for this driver.
  ///
  /// An optional [documentation] builder can provide configuration documentation.
  /// Set [overrideExisting] to `true` to replace an existing registration; otherwise,
  /// a [ProviderConfigException] will be thrown if the driver already exists.
  ///
  /// An optional [configBuilder] can be provided to modify or augment the
  /// user-supplied configuration for this driver.
  ///
  /// An optional [validator] can be provided for additional configuration checks.
  ///
  /// [requiresConfig] specifies a list of configuration keys that must be present
  /// and non-null for this driver to be valid.
  ///
  /// ```dart
  /// CacheDriverRegistry.instance.register(
  ///   'custom',
  ///   () => MyCustomStoreFactory(),
  ///   documentation: (context) => [
  ///     ConfigDocEntry(path: context.path('key'), type: 'string', description: 'API key.'),
  ///   ],
  /// );
  /// ```
  void register(
    String driver,
    StoreFactoryBuilder builder, {
    CacheDriverDocBuilder? documentation,
    bool overrideExisting = true,
    DriverConfigBuilder? configBuilder,
    DriverConfigValidator? validator,
    List<String> requiresConfig = const [],
  }) {
    registerEntry(
      driver,
      CacheDriverRegistration(
        builder: builder,
        documentation: documentation,
        validator: validator,
        requiresConfig: requiresConfig,
        configBuilder: configBuilder,
      ),
      overrideExisting: overrideExisting,
    );
  }

  /// Unregisters a cache driver from the registry.
  ///
  /// Removes the driver identified by [driver] from the list of available drivers.
  ///
  /// ```dart
  /// CacheDriverRegistry.instance.unregister('custom');
  /// ```
  void unregister(String driver) => unregisterEntry(driver);

  /// Whether the registry contains a driver with the given [driver] name.
  ///
  /// Returns `true` if the driver is registered, `false` otherwise.
  ///
  /// ```dart
  /// print(CacheDriverRegistry.instance.contains('file')); // true
  /// print(CacheDriverRegistry.instance.contains('unknown')); // false
  /// ```
  bool contains(String driver) => containsEntry(driver);

  /// A list of all registered cache driver names.
  ///
  /// ```dart
  /// print(CacheDriverRegistry.instance.drivers); // ['array', 'file', 'null', 'redis']
  /// ```
  List<String> get drivers => entryNames.toList(growable: false);

  /// Retrieves the [StoreFactoryBuilder] for the specified [driver].
  ///
  /// Returns `null` if the driver is not registered.
  StoreFactoryBuilder? builderFor(String driver) => getEntry(driver)?.builder;

  /// Populates a [CacheManager] with all registered store factories.
  ///
  /// Iterates through all registered drivers and registers their corresponding
  /// [StoreFactory] instances with the provided [manager].
  ///
  /// ```dart
  /// final manager = CacheManager();
  /// CacheDriverRegistry.instance.populate(manager);
  /// // Now the manager knows about all registered drivers.
  /// ```
  void populate(CacheManager manager) {
    for (final entry in entries.entries) {
      manager.registerStoreFactory(entry.key, entry.value.builder());
    }
  }

  /// Builds the final configuration for [driver] using the supplied [container].
  ///
  /// This method first applies any registered [DriverConfigBuilder] and then
  /// validates the configuration against [requiresConfig] and any custom
  /// [DriverConfigValidator].
  ///
  /// Throws an [ArgumentError] if the [driver] is not registered.
  /// Throws a [ConfigurationException] if the configuration is invalid.
  Map<String, dynamic> buildConfig(
    String driver,
    Map<String, dynamic> userConfig,
    Container container,
  ) {
    final registration = getEntry(driver);
    if (registration == null) {
      throw ArgumentError('Cache driver "$driver" is not registered');
    }

    final context = DriverConfigContext(
      userConfig: Map<String, dynamic>.unmodifiable(userConfig),
      container: container,
      driverName: driver,
    );

    final config =
        registration.configBuilder?.call(context) ??
        Map<String, dynamic>.from(userConfig);

    for (final key in registration.requiresConfig) {
      if (!config.containsKey(key)) {
        throw ConfigurationException(
          'Cache driver "$driver" requires configuration key "$key" '
          'but it was not provided. Please add "$key" to your '
          'cache.stores.$driver configuration.',
        );
      }
      if (config[key] == null) {
        throw ConfigurationException(
          'Cache driver "$driver" requires non-null value for "$key".',
        );
      }
    }

    try {
      registration.validator?.call(config, driver);
    } catch (error) {
      if (error is ConfigurationException) {
        rethrow;
      }
      throw ConfigurationException(
        'Cache driver "$driver" configuration validation failed: $error',
      );
    }

    return config;
  }

  @override
  bool onDuplicate(
    String name,
    CacheDriverRegistration existing,
    bool overrideExisting,
  ) {
    if (!overrideExisting) {
      return false;
    }
    throw ProviderConfigException(
      'Cache driver "$name" is already registered.'
      '${duplicateDiagnostics(name)}',
    );
  }
}

/// The CacheManager class is responsible for managing multiple cache stores.
///
/// It allows registering, retrieving, and resolving cache stores based on their configurations.
class CacheManager {
  /// A map to store the registered repositories.
  ///
  /// The key is the name of the store, and the value is the corresponding [Repository] instance.
  final Map<String, Repository> _repositories = {};

  /// A map to store the configurations of the cache stores.
  ///
  /// The key is the name of the store, and the value is a map containing the configuration details.
  final Map<String, Map<String, dynamic>> _configurations = {};

  /// An optional [EventManager] used for publishing cache-related events.
  EventManager? _eventManager;

  /// The global prefix applied to all keys managed by this [CacheManager].
  String _prefix = '';

  /// An optional [Container] used for resolving driver configuration dependencies.
  final Container? _container;

  /// A registry of [StoreFactory] instances for different cache drivers.
  ///
  /// The key is the driver name (e.g., 'file', 'redis'), and the value is the
  /// corresponding [StoreFactory] instance.
  final Map<String, StoreFactory> _storeFactories = {};

  /// Creates a [CacheManager] instance.
  ///
  /// Initializes the manager and registers the default store factories
  /// provided by the [CacheDriverRegistry].
  ///
  /// - [events]: An optional [EventManager] to attach for cache events.
  /// - [prefix]: An optional global prefix to apply to all cache keys.
  /// - [container]: An optional [Container] for resolving dependencies during driver configuration.
  ///
  /// ```dart
  /// final manager = CacheManager(prefix: 'my_app');
  /// final repository = manager.store('default');
  /// repository.put('key', 'value'); // This might become 'my_app:key'
  /// ```
  CacheManager({EventManager? events, String prefix = '', Container? container})
    : _eventManager = events,
      _prefix = prefix,
      _container = container {
    _ensureDefaultDriversRegistered();
    CacheDriverRegistry.instance.populate(this);
  }

  /// Registers a new cache store configuration under the given [name].
  ///
  /// The [config] map defines the driver and specific settings for this store.
  /// Optionally, a prebuilt [repository] can be directly provided, bypassing
  /// resolution.
  ///
  /// ```dart
  /// manager.registerStore(
  ///   'local_file_cache',
  ///   {'driver': 'file', 'path': '/tmp/cache_files'},
  /// );
  ///
  /// manager.registerStore(
  ///   'my_array_cache',
  ///   {'driver': 'array'},
  ///   repository: ArrayRepository('my_array_cache', 'my_prefix'),
  /// );
  /// ```
  void registerStore(
    String name,
    Map<String, dynamic> config, {
    Repository? repository,
  }) {
    _configurations[name] = config;
    if (repository != null) {
      if (repository is RepositoryImpl) {
        repository.updatePrefix(_prefix);
        repository.attachEventManager(_eventManager);
      }
      _repositories[name] = repository;
    }
  }

  /// Whether a configuration exists for the cache store [name].
  ///
  /// Returns `true` if a store with [name] has been registered, `false` otherwise.
  ///
  /// ```dart
  /// manager.registerStore('test_store', {'driver': 'array'});
  /// print(manager.hasStore('test_store')); // true
  /// print(manager.hasStore('non_existent')); // false
  /// ```
  bool hasStore(String name) => _configurations.containsKey(name);

  /// A list of the names of all registered cache store configurations.
  ///
  /// ```dart
  /// manager.registerStore('store1', {'driver': 'array'});
  /// manager.registerStore('store2', {'driver': 'file'});
  /// print(manager.storeNames); // ['store1', 'store2']
  /// ```
  List<String> get storeNames => _configurations.keys.toList(growable: false);

  /// Retrieves the [Repository] for the given store [name].
  ///
  /// If the repository for [name] has not been resolved yet, it will be
  /// resolved using the registered configuration and the corresponding
  /// [StoreFactory]. Resolved repositories are cached for subsequent access.
  ///
  /// Throws an [ArgumentError] if the store configuration is not defined
  /// or the driver is not supported.
  ///
  /// ```dart
  /// // Assuming 'default' store is configured with 'file' driver
  /// final defaultRepo = manager.store('default');
  /// defaultRepo.put('user:1', {'name': 'Alice'});
  /// ```
  Repository store(String name) {
    return _repositories[name] ??= resolve(name);
  }

  /// Attaches an [EventManager] so repositories can publish cache events.
  ///
  /// This updates all currently resolved [RepositoryImpl] instances with the
  /// new event manager.
  ///
  /// ```dart
  /// final eventManager = EventManager();
  /// manager.attachEventManager(eventManager);
  /// manager.store('default').put('key', 'value'); // Might now publish a CacheHit/CacheMiss event.
  /// ```
  void attachEventManager(EventManager eventManager) {
    _eventManager = eventManager;
    _repositories.updateAll((_, repository) {
      if (repository is RepositoryImpl) {
        repository.attachEventManager(eventManager);
      }
      return repository;
    });
  }

  /// Sets a new global prefix for all cache keys.
  ///
  /// This updates the prefix for all currently resolved [RepositoryImpl] instances.
  /// New repositories resolved after this call will also use the new prefix.
  ///
  /// ```dart
  /// final manager = CacheManager();
  /// manager.setPrefix('v2_');
  /// manager.store('default').put('user_id', 123); // Stores as 'v2_user_id'
  /// ```
  void setPrefix(String prefix) {
    _prefix = prefix;
    _repositories.updateAll((_, repository) {
      if (repository is RepositoryImpl) {
        repository.updatePrefix(prefix);
      }
      return repository;
    });
  }

  /// The current global prefix applied to all cache keys.
  String get prefix => _prefix;

  /// Builds a [Repository] instance from the configuration of the store [name].
  ///
  /// This method is responsible for looking up the store's configuration,
  /// resolving the appropriate [StoreFactory], building the driver's
  /// configuration using [CacheDriverRegistry.buildConfig], creating the
  /// underlying store, and wrapping it in a [RepositoryImpl].
  ///
  /// Throws an [ArgumentError] if the cache store configuration is not defined
  /// or the driver is not supported.
  ///
  /// ```dart
  /// final manager = CacheManager();
  /// manager.registerStore('my_custom_store', {'driver': 'array'});
  /// final repository = manager.resolve('my_custom_store');
  /// ```
  Repository resolve(String name) {
    final config = _configurations[name];
    if (config == null) {
      throw ArgumentError('Cache store [$name] is not defined.');
    }
    final driver = config['driver'];
    final factory = _storeFactories[driver];

    if (factory == null) {
      throw ArgumentError(
        'Driver [$driver] is not supported. Supported drivers are: ${_storeFactories.keys.join(", ")}.',
      );
    }

    final container = _container;
    final resolvedConfig = container != null
        ? CacheDriverRegistry.instance.buildConfig(
            driver.toString(),
            config,
            container,
          )
        : config;

    // Create the underlying store using the factory.
    final storeInstance = factory.create(resolvedConfig);
    final repository = RepositoryImpl(storeInstance, name, _prefix);
    if (_eventManager != null) {
      repository.attachEventManager(_eventManager);
    }
    return repository;
  }

  /// Allows registering custom [StoreFactory] instances for new drivers.
  ///
  /// The [driver] is the unique identifier for the store type.
  /// The [factory] is the concrete factory implementation.
  ///
  /// This is primarily for registering factories that aren't managed by
  /// the [CacheDriverRegistry] or for direct, ad-hoc registration.
  /// For global, reusable driver registration, use [CacheManager.registerDriver].
  ///
  /// ```dart
  /// class CustomStoreFactory implements StoreFactory { /* ... */ }
  /// manager.registerStoreFactory('custom_driver', CustomStoreFactory());
  /// manager.registerStore('my_custom_cache', {'driver': 'custom_driver'});
  /// ```
  void registerStoreFactory(String driver, StoreFactory factory) {
    _storeFactories[driver] = factory;
  }

  /// Registers a cache driver globally so future managers can resolve it.
  ///
  /// This convenience method delegates to [CacheDriverRegistry.instance.register].
  /// It allows for persistent registration of custom drivers that can be
  /// accessed by any [CacheManager] instance.
  ///
  /// - [driver]: A unique identifier for the cache driver.
  /// - [builder]: A function that creates the [StoreFactory] for this driver.
  /// - [documentation]: Optional builder for configuration documentation.
  /// - [overrideExisting]: Whether to replace an existing registration. Defaults to `true`.
  /// - [configBuilder]: Optional builder to process driver configuration.
  /// - [validator]: Optional validator for the driver's configuration.
  /// - [requiresConfig]: List of mandatory configuration keys for this driver.
  ///
  /// ```dart
  /// // Register a custom 'memory' driver globally
  /// class InMemoryStoreFactory implements StoreFactory { /* ... */ }
  /// CacheManager.registerDriver(
  ///   'memory',
  ///   () => InMemoryStoreFactory(),
  ///   documentation: (context) => [
  ///     ConfigDocEntry(path: context.path('capacity'), type: 'int', description: 'Max items.'),
  ///   ],
  /// );
  ///
  /// // Any CacheManager instance can now use 'memory' driver:
  /// final manager = CacheManager();
  /// manager.registerStore('ephemeral', {'driver': 'memory', 'capacity': 100});
  /// ```
  static void registerDriver(
    String driver,
    StoreFactoryBuilder builder, {
    CacheDriverDocBuilder? documentation,
    bool overrideExisting = true,
    DriverConfigBuilder? configBuilder,
    DriverConfigValidator? validator,
    List<String> requiresConfig = const [],
  }) {
    CacheDriverRegistry.instance.register(
      driver,
      builder,
      documentation: documentation,
      overrideExisting: overrideExisting,
      configBuilder: configBuilder,
      validator: validator,
      requiresConfig: requiresConfig,
    );
  }

  /// Removes a previously registered global cache driver.
  ///
  /// This convenience method delegates to [CacheDriverRegistry.instance.unregister].
  ///
  /// ```dart
  /// CacheManager.unregisterDriver('memory');
  /// ```
  static void unregisterDriver(String driver) {
    CacheDriverRegistry.instance.unregister(driver);
  }

  /// A list of all known driver identifiers, including built-in drivers.
  ///
  /// This method ensures that default drivers are registered before listing them.
  ///
  /// ```dart
  /// print(CacheManager.registeredDrivers); // e.g., ['array', 'file', 'null', 'redis', 'memory']
  /// ```
  static List<String> get registeredDrivers {
    _ensureDefaultDriversRegistered();
    return CacheDriverRegistry.instance.drivers;
  }

  /// Whether the default drivers (array, file, null, redis) have been registered.
  static bool _defaultsRegistered = false;

  /// Retrieves the configuration documentation for all registered drivers.
  ///
  /// This method ensures that default drivers are registered before generating
  /// documentation. The [pathBase] is used as the root for configuration keys
  /// in the generated documentation entries.
  ///
  /// ```dart
  /// final docs = CacheManager.driverDocumentation(pathBase: 'my_app.cache_config');
  /// // docs will contain entries like 'my_app.cache_config.file.path'
  /// ```
  static List<ConfigDocEntry> driverDocumentation({required String pathBase}) {
    _ensureDefaultDriversRegistered();
    return CacheDriverRegistry.instance.documentation(pathBase: pathBase);
  }

  /// Ensures that the default cache drivers (`array`, `file`, `null`, `redis`) are registered.
  ///
  /// This method is called automatically when accessing [registeredDrivers] or
  /// [driverDocumentation], or when creating a [CacheManager] instance.
  static void _ensureDefaultDriversRegistered() {
    if (_defaultsRegistered) {
      return;
    }
    registerDriver(
      'array',
      () => ArrayStoreFactory(),
      documentation: _arrayDriverDocs,
      overrideExisting: false,
    );
    registerDriver(
      'file',
      () => FileStoreFactory(),
      documentation: _fileDriverDocs,
      overrideExisting: false,
      configBuilder: (context) {
        final config = Map<String, dynamic>.from(context.userConfig);
        final storageDefaults = context.get<StorageDefaults>();
        final appConfig = context.get<Config>();
        final rawPath = config['path'];
        if (rawPath == null || (rawPath is String && rawPath.trim().isEmpty)) {
          if (storageDefaults != null) {
            config['path'] = storageDefaults.frameworkPath('cache');
          } else if (appConfig != null) {
            config['path'] = resolveFrameworkStoragePath(
              appConfig,
              child: 'cache',
            );
          } else {
            config['path'] = 'storage/framework/cache';
          }
        } else if (rawPath is String) {
          if (storageDefaults != null) {
            config['path'] = storageDefaults.resolve(rawPath);
          } else if (appConfig != null) {
            config['path'] = normalizeStoragePath(appConfig, rawPath);
          }
        }
        return config;
      },
      validator: (config, driver) {
        final path = config['path'];
        if (path is! String || path.trim().isEmpty) {
          throw ConfigurationException(
            'Cache driver "$driver" requires a non-empty "path" '
            'configuration. Add a valid directory path to '
            'cache.stores.<name>.path.',
          );
        }
        final permission = config['permission'];
        if (permission != null && permission is! int) {
          if (permission is num) {
            config['permission'] = permission.toInt();
          } else if (permission is String) {
            final trimmed = permission.trim();
            final parsed =
                int.tryParse(trimmed, radix: 8) ?? int.tryParse(trimmed);
            if (parsed == null) {
              throw ConfigurationException(
                'Cache driver "$driver" permission must be an integer '
                'value (decimal or octal string). Received "$permission".',
              );
            }
            config['permission'] = parsed;
          } else {
            throw ConfigurationException(
              'Cache driver "$driver" permission must be an integer or '
              'string value. Received type ${permission.runtimeType}.',
            );
          }
        }
      },
      requiresConfig: const ['path'],
    );
    registerDriver(
      'null',
      () => NullStoreFactory(),
      documentation: _nullDriverDocs,
      overrideExisting: false,
    );
    registerDriver(
      'redis',
      () => RedisStoreFactory(),
      documentation: _redisDriverDocs,
      overrideExisting: false,
      validator: (config, driver) {
        final url = config['url'];
        if (url != null) {
          if (url is! String) {
            throw ConfigurationException(
              'Cache driver "$driver" url must be a string. '
              'Received type ${url.runtimeType}.',
            );
          }
          final trimmed = url.trim();
          if (trimmed.isNotEmpty) {
            final parsed = Uri.tryParse(trimmed);
            if (parsed == null || parsed.host.isEmpty) {
              throw ConfigurationException(
                'Cache driver "$driver" url must be a valid Redis URL '
                '(for example redis://localhost:6379/0).',
              );
            }
            config['url'] = trimmed;
          } else {
            config.remove('url');
          }
        }

        final host = config['host'];
        if (host != null && host is! String) {
          throw ConfigurationException(
            'Cache driver "$driver" host must be a string. '
            'Received type ${host.runtimeType}.',
          );
        }

        void coerceInt(String key) {
          final value = config[key];
          if (value == null) {
            return;
          }
          if (value is int) {
            return;
          }
          if (value is num) {
            config[key] = value.toInt();
            return;
          }
          final parsed = int.tryParse(value.toString());
          if (parsed == null) {
            throw ConfigurationException(
              'Cache driver "$driver" $key must be an integer value. '
              'Received "$value".',
            );
          }
          config[key] = parsed;
        }

        coerceInt('port');
        coerceInt('database');
        coerceInt('db');

        final password = config['password'];
        if (password != null && password is! String) {
          throw ConfigurationException(
            'Cache driver "$driver" password must be a string. '
            'Received type ${password.runtimeType}.',
          );
        }
      },
    );
    _defaultsRegistered = true;
  }

  /// Provides configuration documentation for the `array` cache driver.
  ///
  /// This driver stores cache items in an in-memory array and is not persistent.
  static List<ConfigDocEntry> _arrayDriverDocs(CacheDriverDocContext context) =>
      const <ConfigDocEntry>[];

  /// Provides configuration documentation for the `file` cache driver.
  ///
  /// This driver stores cache items as files on the local filesystem.
  static List<ConfigDocEntry> _fileDriverDocs(CacheDriverDocContext context) {
    return <ConfigDocEntry>[
      ConfigDocEntry(
        path: context.path('path'),
        type: 'string',
        description:
            'The directory where cache files are stored. If omitted, defaults to '
            'storage/framework/cache based on your application\'s storage configuration.',
        metadata: const {
          'default_note':
              'Computed from storage defaults (storage/framework/cache).',
          'validation': 'Must resolve to a non-empty directory path.',
        },
      ),
      ConfigDocEntry(
        path: context.path('permission'),
        type: 'int',
        description:
            'An optional file permission mask (octal or decimal) applied to '
            'created cache files. For example, `0644` for read/write by owner, read-only by group/others.',
        metadata: const {
          'validation': 'Provide octal (e.g. 0644) or decimal file mode.',
        },
      ),
    ];
  }

  /// Provides configuration documentation for the `null` cache driver.
  ///
  /// This driver discards all cache operations, effectively providing a no-op cache.
  static List<ConfigDocEntry> _nullDriverDocs(CacheDriverDocContext context) =>
      const <ConfigDocEntry>[];

  /// Provides configuration documentation for the `redis` cache driver.
  ///
  /// This driver stores cache items in a Redis key-value store.
  static List<ConfigDocEntry> _redisDriverDocs(
    CacheDriverDocContext context,
  ) => <ConfigDocEntry>[
    ConfigDocEntry(
      path: context.path('url'),
      type: 'string',
      description:
          'An optional Redis connection URL. When provided, this URL '
          'overrides the [host], [port], [password], and [db] configurations. '
          'Example: `redis://username:password@localhost:6379/0`.',
      metadata: const {
        'validation': 'Must be a valid redis:// URL including host.',
      },
    ),
    ConfigDocEntry(
      path: context.path('host'),
      type: 'string',
      description: 'The Redis host to connect to when [url] is not provided.',
      defaultValue: '127.0.0.1',
      metadata: const {'default_note': 'Ignored when [url] is provided.'},
    ),
    ConfigDocEntry(
      path: context.path('port'),
      type: 'int',
      description: 'The Redis port to connect to when [url] is not provided.',
      defaultValue: 6379,
      metadata: const {
        'default_note': 'Ignored when [url] is provided.',
        'validation': 'Must be an integer.',
      },
    ),
    ConfigDocEntry(
      path: context.path('password'),
      type: 'string',
      description: 'An optional Redis password for authentication.',
      metadata: const {'default_note': 'Optional; omit for no authentication.'},
    ),
    ConfigDocEntry(
      path: context.path('db'),
      type: 'int',
      description:
          'The Redis database index to select after connecting. '
          'This setting can also be specified using the `database` alias.',
      defaultValue: 0,
      metadata: const {
        'default_note': 'Overrides apply when `database` or `db` is set.',
        'validation': 'Must be an integer.',
      },
    ),
  ];

  /// Retrieves the name of the default driver for this [CacheManager].
  ///
  /// The default driver is determined by the first registered store configuration.
  ///
  /// Throws a [StateError] if no stores have been registered with the manager.
  ///
  /// ```dart
  /// final manager = CacheManager();
  /// manager.registerStore('primary', {'driver': 'file'});
  /// manager.registerStore('secondary', {'driver': 'redis'});
  /// print(manager.getDefaultDriver()); // 'primary'
  /// ```
  String getDefaultDriver() {
    if (_configurations.isEmpty) {
      throw StateError('No stores have been registered.');
    }
    return _configurations.keys.first;
  }
}
