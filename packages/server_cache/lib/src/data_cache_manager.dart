import 'package:server_contracts/server_contracts.dart' show Repository, Store;

import 'repository.dart';
import 'store_factory.dart';

/// Builds repository callbacks for a specific configured store.
typedef DataCacheCallbacksBuilder =
    RepositoryEventCallbacks? Function(String storeName);

/// Framework-agnostic cache manager for [Repository] instances.
///
/// Stores are registered as concrete [Store] objects. When an application
/// wants reusable construction, [registerStoreFactory] accepts a typed
/// [StoreConfiguration] and creates the store during composition. The
/// manager never parses string-keyed configuration maps.
class DataCacheManager {
  DataCacheManager({
    String prefix = '',
    DataCacheCallbacksBuilder? callbacksBuilder,
  }) : _prefix = prefix,
       _callbacksBuilder = callbacksBuilder;

  final Map<String, Repository> _repositories = <String, Repository>{};
  final Map<String, Store> _stores = <String, Store>{};

  String _prefix;
  DataCacheCallbacksBuilder? _callbacksBuilder;

  /// Registers a concrete store under [name].
  void registerStore(String name, Store store, {Repository? repository}) {
    _stores[name] = store;
    _repositories.remove(name);
    if (repository != null) {
      _repositories[name] = _configureRepository(name, repository);
    }
  }

  /// Creates and registers a store from typed [configuration].
  void registerStoreFactory<T extends StoreConfiguration>(
    String name,
    StoreFactory<T> factory,
    T configuration, {
    Repository? repository,
  }) {
    registerStore(name, factory.create(configuration), repository: repository);
  }

  /// Returns whether [name] has a registered store.
  bool hasStore(String name) => _stores.containsKey(name);

  /// Names of all registered stores.
  List<String> get storeNames => _stores.keys.toList(growable: false);

  /// Resolves (or returns cached) [Repository] for [name].
  Repository store(String name) {
    return _repositories[name] ??= resolve(name);
  }

  /// Resolves a fresh [Repository] for [name].
  Repository resolve(String name) {
    final store = _stores[name];
    if (store == null) {
      throw ArgumentError('Cache store [$name] is not defined.');
    }
    return RepositoryImpl(store, name, _prefix, _callbacksBuilder?.call(name));
  }

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

  /// Updates callbacks and reapplies them to resolved repositories.
  void setCallbacksBuilder(DataCacheCallbacksBuilder? builder) {
    _callbacksBuilder = builder;
    for (final entry in _repositories.entries) {
      final repository = entry.value;
      if (repository is RepositoryImpl) {
        repository.attachCallbacks(builder?.call(entry.key));
      }
    }
  }

  /// Clears cached resolved repositories while preserving registered stores.
  void clearResolvedStores() {
    _repositories.clear();
  }

  /// Clears all registered and resolved stores.
  void clear() {
    _repositories.clear();
    _stores.clear();
  }

  /// Returns the first registered store name.
  String getDefaultStoreName() {
    if (_stores.isEmpty) {
      throw StateError('No stores have been registered.');
    }
    return _stores.keys.first;
  }

  Repository _configureRepository(String name, Repository repository) {
    if (repository is RepositoryImpl) {
      repository
        ..updatePrefix(_prefix)
        ..attachCallbacks(_callbacksBuilder?.call(name));
    }
    return repository;
  }
}
