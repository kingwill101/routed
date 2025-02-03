import 'package:routed/src/contracts/cache/repository.dart';
import 'package:routed/src/cache/repository.dart';
import 'package:routed/src/cache/store_factory.dart';
import 'package:routed/src/cache/array_store_factory.dart';
import 'package:routed/src/cache/file_store_factory.dart';

/// The CacheManager class is responsible for managing multiple cache stores.
/// It allows registering, retrieving, and resolving cache stores based on their configurations.
class CacheManager {
  /// A map to store the registered repositories.
  /// The key is the name of the store, and the value is the corresponding Repository instance.
  final Map<String, Repository> _repositories = {};

  /// A map to store the configurations of the cache stores.
  /// The key is the name of the store, and the value is a map containing the configuration details.
  final Map<String, Map<String, dynamic>> _configurations = {};

  /// A registry of store factories.
  /// The key is the driver name, and the value is the corresponding StoreFactory instance.
  final Map<String, StoreFactory> _storeFactories = {};

  /// Constructor for CacheManager.
  /// Initializes the CacheManager and registers the default store factories.
  CacheManager() {
    // Register default factories.
    _storeFactories['array'] = ArrayStoreFactory();
    _storeFactories['file'] = FileStoreFactory();
  }

  /// Registers a new cache store configuration under the given [name].
  /// Optionally, a prebuilt [repository] can be directly provided.
  ///
  /// - Parameters:
  ///   - name: The name of the cache store.
  ///   - config: A map containing the configuration details for the cache store.
  ///   - repository: An optional prebuilt Repository instance.
  void registerStore(String name, Map<String, dynamic> config,
      {Repository? repository}) {
    _configurations[name] = config;
    if (repository != null) {
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
      throw ArgumentError('Driver [$driver] is not supported. Supported drivers are: ${_storeFactories.keys.join(", ")}.');
    }
    // Create the underlying store using the factory.
    final storeInstance = factory.create(config);
    return RepositoryImpl(storeInstance);
  }

  /// Allows registering custom store factories.
  ///
  /// - Parameters:
  ///   - driver: The name of the driver.
  ///   - factory: The StoreFactory instance to be registered.
  void registerStoreFactory(String driver, StoreFactory factory) {
    _storeFactories[driver] = factory;
  }

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
