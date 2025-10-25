// ignore_for_file: library_private_types_in_public_api

import 'package:routed/src/cache/array_store_factory.dart';
import 'package:routed/src/cache/file_store_factory.dart';
import 'package:routed/src/cache/null_store_factory.dart';
import 'package:routed/src/cache/redis_store_factory.dart';
import 'package:routed/src/cache/repository.dart';
import 'package:routed/src/cache/store_factory.dart';
import 'package:routed/src/contracts/cache/repository.dart';
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/events/event_manager.dart';
import 'package:routed/src/engine/storage_defaults.dart';
import 'package:routed/src/engine/storage_paths.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/support/named_registry.dart';

typedef StoreFactoryBuilder = StoreFactory Function();
typedef CacheDriverDocBuilder =
    List<ConfigDocEntry> Function(CacheDriverDocContext context);

class CacheDriverDocContext {
  CacheDriverDocContext({required this.driver, required this.pathTemplate});

  final String driver;
  final String pathTemplate;

  String path(String segment) => '$pathTemplate.$segment';
}

/// Context provided to cache driver configuration builders.
class DriverConfigContext {
  DriverConfigContext({
    required this.userConfig,
    required this.container,
    required this.driverName,
  });

  /// Original configuration supplied by the user/provider.
  final Map<String, dynamic> userConfig;

  /// Application service container for looking up dependencies.
  final Container container;

  /// Normalized driver identifier.
  final String driverName;

  /// Attempts to synchronously resolve [T] from the container.
  ///
  /// Returns `null` when the service is unavailable or cannot be resolved
  /// synchronously.
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

/// Builder that constructs the final configuration for a driver.
typedef DriverConfigBuilder =
    Map<String, dynamic> Function(DriverConfigContext context);

/// Validator invoked after configuration has been built.
typedef DriverConfigValidator =
    void Function(Map<String, dynamic> config, String driverName);

/// Exception raised when driver configuration is invalid.
class ConfigurationException implements Exception {
  const ConfigurationException(this.message);

  final String message;

  @override
  String toString() => 'ConfigurationException: $message';
}

class _CacheDriverRegistration {
  _CacheDriverRegistration({
    required this.builder,
    required this.origin,
    this.documentation,
    this.configBuilder,
    this.validator,
    this.requiresConfig = const [],
  });

  final StoreFactoryBuilder builder;
  final StackTrace origin;
  final CacheDriverDocBuilder? documentation;
  final DriverConfigBuilder? configBuilder;
  final DriverConfigValidator? validator;
  final List<String> requiresConfig;
}

class CacheDriverRegistry extends NamedRegistry<_CacheDriverRegistration> {
  CacheDriverRegistry._internal();

  static final CacheDriverRegistry instance = CacheDriverRegistry._internal();

  void register(
    String driver,
    StoreFactoryBuilder builder, {
    CacheDriverDocBuilder? documentation,
    bool overrideExisting = true,
    DriverConfigBuilder? configBuilder,
    DriverConfigValidator? validator,
    List<String> requiresConfig = const [],
  }) {
    final registration = _CacheDriverRegistration(
      builder: builder,
      origin: StackTrace.current,
      documentation: documentation,
      configBuilder: configBuilder,
      validator: validator,
      requiresConfig: requiresConfig,
    );
    final stored = registerEntry(
      driver,
      registration,
      overrideExisting: overrideExisting,
    );
    if (!stored) {
      return;
    }
  }

  void unregister(String driver) => unregisterEntry(driver);

  bool contains(String driver) => containsEntry(driver);

  List<String> get drivers => entryNames.toList(growable: false);

  StoreFactoryBuilder? builderFor(String driver) => getEntry(driver)?.builder;

  void populate(CacheManager manager) {
    for (final entry in entries.entries) {
      manager.registerStoreFactory(entry.key, entry.value.builder());
    }
  }

  List<ConfigDocEntry> documentation({required String pathTemplate}) {
    final docs = <ConfigDocEntry>[];
    entries.forEach((driver, registration) {
      final builder = registration.documentation;
      if (builder == null) {
        return;
      }
      final entries = builder(
        CacheDriverDocContext(driver: driver, pathTemplate: pathTemplate),
      );
      if (entries.isNotEmpty) {
        docs.addAll(entries);
      }
    });
    return docs;
  }

  /// Builds the final configuration for [driver] using the supplied [container].
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
    _CacheDriverRegistration existing,
    bool overrideExisting,
  ) {
    if (!overrideExisting) {
      return false;
    }
    throw ProviderConfigException(
      'Cache driver "$name" is already registered.\n'
      'Original registration stack trace:\n${existing.origin}',
    );
  }
}

/// The CacheManager class is responsible for managing multiple cache stores.
/// It allows registering, retrieving, and resolving cache stores based on their configurations.
class CacheManager {
  /// A map to store the registered repositories.
  /// The key is the name of the store, and the value is the corresponding Repository instance.
  final Map<String, Repository> _repositories = {};

  /// A map to store the configurations of the cache stores.
  /// The key is the name of the store, and the value is a map containing the configuration details.
  final Map<String, Map<String, dynamic>> _configurations = {};

  /// Optional event manager used for cache events.
  EventManager? _eventManager;
  String _prefix = '';
  final Container? _container;

  /// A registry of store factories.
  /// The key is the driver name, and the value is the corresponding StoreFactory instance.
  final Map<String, StoreFactory> _storeFactories = {};

  /// Constructor for CacheManager.
  /// Initializes the CacheManager and registers the default store factories.
  CacheManager({EventManager? events, String prefix = '', Container? container})
    : _eventManager = events,
      _prefix = prefix,
      _container = container {
    _ensureDefaultDriversRegistered();
    CacheDriverRegistry.instance.populate(this);
  }

  /// Registers a new cache store configuration under the given [name].
  /// Optionally, a prebuilt [repository] can be directly provided.
  ///
  /// - Parameters:
  ///   - name: The name of the cache store.
  ///   - config: A map containing the configuration details for the cache store.
  ///   - repository: An optional prebuilt Repository instance.
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

  /// Returns `true` if a configuration exists for the cache store [name].
  bool hasStore(String name) => _configurations.containsKey(name);

  /// Lists the names of all registered cache store configurations.
  List<String> get storeNames => _configurations.keys.toList(growable: false);

  /// Retrieves the repository for the given store [name].
  ///
  /// - Parameters:
  ///   - name: The name of the cache store.
  ///
  /// - Returns: The Repository instance associated with the given store name.
  Repository store(String name) {
    return _repositories[name] ??= resolve(name);
  }

  /// Attach an event manager so repositories can publish cache events.
  void attachEventManager(EventManager eventManager) {
    _eventManager = eventManager;
    _repositories.updateAll((_, repository) {
      if (repository is RepositoryImpl) {
        repository.attachEventManager(eventManager);
      }
      return repository;
    });
  }

  void setPrefix(String prefix) {
    _prefix = prefix;
    _repositories.updateAll((_, repository) {
      if (repository is RepositoryImpl) {
        repository.updatePrefix(prefix);
      }
      return repository;
    });
  }

  String get prefix => _prefix;

  /// Builds a repository instance from the configuration.
  ///
  /// - Parameters:
  ///   - name: The name of the cache store.
  ///
  /// - Returns: The Repository instance built from the configuration.
  ///
  /// - Throws: ArgumentError if the cache store configuration is not defined or the driver is not supported.
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

  /// Allows registering custom store factories.
  ///
  /// - Parameters:
  ///   - driver: The name of the driver.
  ///   - factory: The StoreFactory instance to be registered.
  void registerStoreFactory(String driver, StoreFactory factory) {
    _storeFactories[driver] = factory;
  }

  /// Registers a cache driver globally so future managers can resolve it.
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
  static void unregisterDriver(String driver) {
    CacheDriverRegistry.instance.unregister(driver);
  }

  /// Lists all known driver identifiers, including built-ins.
  static List<String> get registeredDrivers {
    _ensureDefaultDriversRegistered();
    return CacheDriverRegistry.instance.drivers;
  }

  static bool _defaultsRegistered = false;

  static List<ConfigDocEntry> driverDocumentation({
    required String pathTemplate,
  }) {
    _ensureDefaultDriversRegistered();
    return CacheDriverRegistry.instance.documentation(
      pathTemplate: pathTemplate,
    );
  }

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

  static List<ConfigDocEntry> _arrayDriverDocs(CacheDriverDocContext context) =>
      const <ConfigDocEntry>[];

  static List<ConfigDocEntry> _fileDriverDocs(CacheDriverDocContext context) {
    return <ConfigDocEntry>[
      ConfigDocEntry(
        path: context.path('path'),
        type: 'string',
        description:
            'Directory where cache files are stored. If omitted, defaults to '
            'storage/framework/cache based on your storage configuration.',
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
            'Optional file permission mask (octal or decimal) applied to '
            'created cache files.',
        metadata: const {
          'validation': 'Provide octal (e.g. 0644) or decimal file mode.',
        },
      ),
    ];
  }

  static List<ConfigDocEntry> _nullDriverDocs(CacheDriverDocContext context) =>
      const <ConfigDocEntry>[];

  static List<ConfigDocEntry> _redisDriverDocs(CacheDriverDocContext context) =>
      <ConfigDocEntry>[
        ConfigDocEntry(
          path: context.path('url'),
          type: 'string',
          description:
              'Optional Redis connection URL. When provided it overrides host '
              'and port (e.g. redis://localhost:6379/0).',
          metadata: const {
            'validation': 'Must be a valid redis:// URL including host.',
          },
        ),
        ConfigDocEntry(
          path: context.path('host'),
          type: 'string',
          description: 'Redis host when url is not provided.',
          defaultValue: '127.0.0.1',
          metadata: const {'default_note': 'Ignored when url is provided.'},
        ),
        ConfigDocEntry(
          path: context.path('port'),
          type: 'int',
          description: 'Redis port when url is not provided.',
          defaultValue: 6379,
          metadata: const {
            'default_note': 'Ignored when url is provided.',
            'validation': 'Must be an integer.',
          },
        ),
        ConfigDocEntry(
          path: context.path('password'),
          type: 'string',
          description: 'Optional Redis password.',
          metadata: const {'default_note': 'Optional; omit for no auth.'},
        ),
        ConfigDocEntry(
          path: context.path('db'),
          type: 'int',
          description:
              'Database index selected after connecting (aliases: database).',
          defaultValue: 0,
          metadata: const {
            'default_note': 'Overrides apply when `database` or `db` is set.',
            'validation': 'Must be an integer.',
          },
        ),
      ];

  /// Retrieves the default driver name.
  ///
  /// - Returns: The name of the default driver.
  ///
  /// - Throws: StateError if no stores have been registered.
  String getDefaultDriver() {
    if (_configurations.isEmpty) {
      throw StateError('No stores have been registered.');
    }
    return _configurations.keys.first;
  }
}
