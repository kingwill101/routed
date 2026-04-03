import 'package:server_contracts/server_contracts.dart' show Repository;

import 'array_store_factory.dart';
import 'file_store_factory.dart';
import 'null_store_factory.dart';
import 'redis_store_factory.dart';
import 'repository.dart';
import 'store_factory.dart';

/// Resolves cache store configuration before a [StoreFactory] is invoked.
typedef DataCacheConfigResolver =
    Map<String, dynamic> Function(String driver, Map<String, dynamic> config);

/// Builds repository callbacks for a specific configured store.
typedef DataCacheCallbacksBuilder =
    RepositoryEventCallbacks? Function(String storeName);

/// Framework-agnostic cache manager for [Repository] instances.
///
/// This manager owns store configurations, resolves repositories lazily, and
/// delegates concrete storage creation to registered [StoreFactory] instances.
class DataCacheManager {
  DataCacheManager({
    String prefix = '',
    DataCacheConfigResolver? configResolver,
    DataCacheCallbacksBuilder? callbacksBuilder,
    bool registerDefaultStoreFactories = true,
  }) : _prefix = prefix,
       _configResolver = configResolver,
       _callbacksBuilder = callbacksBuilder {
    if (registerDefaultStoreFactories) {
      _registerDefaultStoreFactories();
    }
  }

  final Map<String, Repository> _repositories = <String, Repository>{};
  final Map<String, Map<String, dynamic>> _configurations =
      <String, Map<String, dynamic>>{};
  final Map<String, StoreFactory> _storeFactories = <String, StoreFactory>{};

  String _prefix;
  DataCacheConfigResolver? _configResolver;
  DataCacheCallbacksBuilder? _callbacksBuilder;

  /// Registers a configured store entry.
  ///
  /// When [repository] is provided, it is used directly and no factory
  /// resolution is required for [store].
  void registerStore(
    String name,
    Map<String, dynamic> config, {
    Repository? repository,
  }) {
    _configurations[name] = Map<String, dynamic>.from(config);
    if (repository != null) {
      _repositories[name] = _configureRepository(name, repository);
    }
  }

  /// Returns whether [name] has store configuration.
  bool hasStore(String name) => _configurations.containsKey(name);

  /// Names of all configured stores.
  List<String> get storeNames => _configurations.keys.toList(growable: false);

  /// Resolves (or returns cached) [Repository] for [name].
  Repository store(String name) {
    return _repositories[name] ??= resolve(name);
  }

  /// Resolves a fresh [Repository] for [name] from its configuration.
  Repository resolve(String name) {
    final config = _configurations[name];
    if (config == null) {
      throw ArgumentError('Cache store [$name] is not defined.');
    }

    final driverValue = config['driver'];
    final driver = driverValue?.toString();
    if (driver == null || driver.isEmpty) {
      throw ArgumentError(
        'Cache store [$name] must define a non-empty "driver".',
      );
    }

    final factory = _storeFactories[driver];
    if (factory == null) {
      throw ArgumentError(
        'Driver [$driver] is not supported. '
        'Supported drivers are: ${_storeFactories.keys.join(", ")}.',
      );
    }

    final resolvedConfig = _resolveConfig(driver, config);
    final repository = RepositoryImpl(
      factory.create(resolvedConfig),
      name,
      _prefix,
      _callbacksBuilder?.call(name),
    );
    return repository;
  }

  /// Registers a [StoreFactory] under [driver].
  void registerStoreFactory(String driver, StoreFactory factory) {
    _storeFactories[driver] = factory;
  }

  /// Returns whether a [StoreFactory] exists for [driver].
  bool hasStoreFactory(String driver) => _storeFactories.containsKey(driver);

  /// Registered store factory driver names.
  List<String> get storeFactoryDrivers =>
      _storeFactories.keys.toList(growable: false);

  /// Updates the key prefix for current and future repositories.
  void setPrefix(String prefix) {
    _prefix = prefix;
    for (final repository in _repositories.values) {
      if (repository is RepositoryImpl) {
        repository.updatePrefix(prefix);
      }
    }
  }

  /// Current key prefix applied by this manager.
  String get prefix => _prefix;

  /// Updates configuration resolver for future repository resolutions.
  ///
  /// Existing cached repositories are retained.
  void setConfigResolver(DataCacheConfigResolver? resolver) {
    _configResolver = resolver;
  }

  /// Updates callbacks builder and reapplies it to resolved repositories.
  void setCallbacksBuilder(DataCacheCallbacksBuilder? builder) {
    _callbacksBuilder = builder;
    for (final entry in _repositories.entries) {
      final repository = entry.value;
      if (repository is RepositoryImpl) {
        repository.attachCallbacks(builder?.call(entry.key));
      }
    }
  }

  /// Clears cached resolved repositories while preserving configuration.
  void clearResolvedStores() {
    _repositories.clear();
  }

  /// Clears all configured and resolved stores.
  void clear() {
    _repositories.clear();
    _configurations.clear();
  }

  /// Returns the first registered store name.
  ///
  /// Throws a [StateError] when no stores are configured.
  String getDefaultDriver() {
    if (_configurations.isEmpty) {
      throw StateError('No stores have been registered.');
    }
    return _configurations.keys.first;
  }

  Map<String, dynamic> _resolveConfig(
    String driver,
    Map<String, dynamic> config,
  ) {
    final copied = Map<String, dynamic>.from(config);
    final resolver = _configResolver;
    if (resolver == null) {
      return copied;
    }
    return Map<String, dynamic>.from(resolver(driver, copied));
  }

  Repository _configureRepository(String name, Repository repository) {
    if (repository is RepositoryImpl) {
      repository
        ..updatePrefix(_prefix)
        ..attachCallbacks(_callbacksBuilder?.call(name));
    }
    return repository;
  }

  void _registerDefaultStoreFactories() {
    registerStoreFactory('array', ArrayStoreFactory());
    registerStoreFactory('file', FileStoreFactory());
    registerStoreFactory('null', NullStoreFactory());
    registerStoreFactory('redis', RedisStoreFactory());
  }
}
