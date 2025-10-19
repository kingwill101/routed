import 'package:routed/src/cache/array_store_factory.dart';
import 'package:routed/src/cache/file_store_factory.dart';
import 'package:routed/src/cache/null_store_factory.dart';
import 'package:routed/src/cache/redis_store_factory.dart';
import 'package:routed/src/cache/repository.dart';
import 'package:routed/src/cache/store_factory.dart';
import 'package:routed/src/contracts/cache/repository.dart';
import 'package:routed/src/events/event_manager.dart';
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

class _CacheDriverRegistration {
  _CacheDriverRegistration({
    required this.builder,
    required this.origin,
    this.documentation,
  });

  final StoreFactoryBuilder builder;
  final StackTrace origin;
  final CacheDriverDocBuilder? documentation;
}

class CacheDriverRegistry extends NamedRegistry<_CacheDriverRegistration> {
  CacheDriverRegistry._internal();

  static final CacheDriverRegistry instance = CacheDriverRegistry._internal();

  void register(
    String driver,
    StoreFactoryBuilder builder, {
    CacheDriverDocBuilder? documentation,
    bool overrideExisting = true,
  }) {
    final registration = _CacheDriverRegistration(
      builder: builder,
      origin: StackTrace.current,
      documentation: documentation,
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

  /// A registry of store factories.
  /// The key is the driver name, and the value is the corresponding StoreFactory instance.
  final Map<String, StoreFactory> _storeFactories = {};

  /// Constructor for CacheManager.
  /// Initializes the CacheManager and registers the default store factories.
  CacheManager({EventManager? events, String prefix = ''})
    : _eventManager = events,
      _prefix = prefix {
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
    // Create the underlying store using the factory.
    final storeInstance = factory.create(config);
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
  }) {
    CacheDriverRegistry.instance.register(
      driver,
      builder,
      documentation: documentation,
      overrideExisting: overrideExisting,
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
            'Directory path where cache files are stored for the file driver.',
      ),
      ConfigDocEntry(
        path: context.path('permission'),
        type: 'int',
        description:
            'File system permission mask applied to created cache files.',
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
          description: 'Redis connection URL (e.g. redis://localhost:6379/0).',
        ),
        ConfigDocEntry(
          path: context.path('host'),
          type: 'string',
          description: 'Redis host when url is not provided.',
        ),
        ConfigDocEntry(
          path: context.path('port'),
          type: 'int',
          description: 'Redis port when url is not provided.',
        ),
        ConfigDocEntry(
          path: context.path('password'),
          type: 'string',
          description: 'Redis password if authentication is required.',
        ),
        ConfigDocEntry(
          path: context.path('db'),
          type: 'int',
          description: 'Database index selected after connecting.',
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
