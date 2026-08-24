import 'package:server_contracts/server_contracts.dart';

/// Optional instrumentation callbacks emitted by a cache repository.
class RepositoryEventCallbacks {
  /// Creates callbacks for cache hits, misses, writes, and removals.
  const RepositoryEventCallbacks({
    this.onHit,
    this.onMiss,
    this.onWrite,
    this.onForget,
  });

  /// Called after `key` is read successfully.
  final void Function(String key)? onHit;

  /// Called when `key` is absent.
  final void Function(String key)? onMiss;

  /// Called after a value is written for `key`.
  final void Function(String key, Duration? ttl)? onWrite;

  /// Called after `key` is removed.
  final void Function(String key)? onForget;
}

/// Prefixing and instrumentation implementation of the [Repository] contract.
///
/// The repository keeps the public key separate from the backend key by
/// prepending [_prefix]. Event callbacks receive the public key, so metrics do
/// not need to know how a store is namespaced.
class RepositoryImpl implements Repository {
  /// Creates a repository around [store] with [storeName] and an initial key
  /// prefix.
  RepositoryImpl(
    this.store,
    this.storeName,
    this._prefix, [
    RepositoryEventCallbacks? callbacks,
  ]) : _callbacks = callbacks;

  /// Store used for persistence.
  final Store store;

  /// Logical store name associated with this repository.
  final String storeName;
  RepositoryEventCallbacks? _callbacks;
  String _prefix;

  /// Replaces event [callbacks] for this repository.
  // The method form is retained as part of the repository configuration API.
  // ignore: use_setters_to_change_properties
  void attachCallbacks(RepositoryEventCallbacks? callbacks) {
    _callbacks = callbacks;
  }

  /// Replaces the key [prefix] used for subsequent operations.
  // The method form is retained as part of the repository configuration API.
  // ignore: use_setters_to_change_properties
  void updatePrefix(String prefix) {
    _prefix = prefix;
  }

  String _prefixed(String key) => _prefix.isEmpty ? key : '$_prefix$key';

  void _publishHit(String key) {
    _callbacks?.onHit?.call(key);
  }

  void _publishMiss(String key) {
    _callbacks?.onMiss?.call(key);
  }

  void _publishWrite(String key, Duration? ttl) {
    _callbacks?.onWrite?.call(key, ttl);
  }

  void _publishForget(String key) {
    _callbacks?.onForget?.call(key);
  }

  /// Retrieves an item from the cache and deletes it.
  ///
  /// If the item is not found, returns the [defaultValue].
  ///
  /// - Parameters:
  ///   - key: The key of the item to retrieve.
  ///   - defaultValue: The value to return if the item is not found.
  /// - Returns: The cached item or the [defaultValue] if the item is not found.
  @override
  Future<dynamic> pull(dynamic key, [dynamic defaultValue]) async {
    final keyString = key is String ? key : key.toString();
    final value = await store.get(_prefixed(keyString));
    if (value == null) {
      _publishMiss(keyString);
      return defaultValue;
    }
    _publishHit(keyString);
    final removed = await store.forget(_prefixed(keyString));
    if (removed) {
      _publishForget(keyString);
    }
    return value;
  }

  /// Returns the value for [key] and removes it from the cache.
  @override
  Future<dynamic> get(String key) async {
    final result = await store.get(_prefixed(key));
    if (result == null) {
      _publishMiss(key);
    } else {
      _publishHit(key);
    }
    return result;
  }

  /// Stores an item in the cache.
  ///
  /// - Parameters:
  ///   - key: The key of the item to store.
  ///   - value: The value of the item to store.
  ///   - ttl: The time-to-live duration for the item.
  /// - Returns: A boolean indicating whether the operation was successful.
  @override
  Future<bool> put(String key, dynamic value, [Duration? ttl]) async {
    final success = await store.put(_prefixed(key), value, ttl?.inSeconds ?? 0);
    if (success) {
      _publishWrite(key, ttl);
    }
    return success;
  }

  /// Stores an item in the cache if the key does not exist.
  ///
  /// - Parameters:
  ///   - key: The key of the item to store.
  ///   - value: The value of the item to store.
  ///   - ttl: The time-to-live duration for the item.
  /// - Returns: A boolean indicating whether the operation was successful.
  @override
  Future<bool> add(String key, dynamic value, [Duration? ttl]) async {
    final existing = await store.get(_prefixed(key));
    if (existing != null) {
      _publishHit(key);
      return false;
    }
    _publishMiss(key);
    // Use the store's atomic store-only-if-absent operation so concurrent
    // callers for the same missing key cannot all report success and
    // clobber each other's values.
    final success = await store.add(_prefixed(key), value, ttl?.inSeconds ?? 0);
    if (success) {
      _publishWrite(key, ttl);
    }
    return success;
  }

  /// Increments the value of an item in the cache.
  ///
  /// - Parameters:
  ///   - key: The key of the item to increment.
  ///   - value: The increment amount (default is 1).
  /// - Returns: The new value after incrementing.
  @override
  Future<dynamic> increment(String key, [dynamic value = 1]) async {
    final incrementValue = value is int ? value : 1;
    final result = await store.increment(_prefixed(key), incrementValue);
    _publishWrite(key, null);
    return result;
  }

  /// Decrements the value of an item in the cache.
  ///
  /// - Parameters:
  ///   - key: The key of the item to decrement.
  ///   - value: The decrement amount (default is 1).
  /// - Returns: The new value after decrementing.
  @override
  Future<dynamic> decrement(String key, [dynamic value = 1]) async {
    final decrementValue = value is int ? value : 1;
    final result = await store.decrement(_prefixed(key), decrementValue);
    _publishWrite(key, null);
    return result;
  }

  /// Stores an item in the cache indefinitely.
  ///
  /// - Parameters:
  ///   - key: The key of the item to store.
  ///   - value: The value of the item to store.
  /// - Returns: A boolean indicating whether the operation was successful.
  @override
  Future<bool> forever(String key, dynamic value) async {
    final success = await store.forever(_prefixed(key), value);
    if (success) {
      _publishWrite(key, null);
    }
    return success;
  }

  /// Gets an item from the cache, or executes the given [callback] and stores
  /// the result.
  ///
  /// - Parameters:
  ///   - key: The key of the item to retrieve.
  ///   - ttl: The time-to-live duration for the item.
  ///   - callback: The function to execute if the item is not found.
  /// - Returns: The cached item or the result of the [callback].
  @override
  Future<dynamic> remember(String key, dynamic ttl, Function callback) async {
    final existing = await store.get(_prefixed(key));
    if (existing != null) {
      _publishHit(key);
      return existing;
    }
    _publishMiss(key);
    final result = await Function.apply(callback, const <dynamic>[]);
    Duration? ttlDuration;
    int seconds;
    if (ttl is Duration) {
      ttlDuration = ttl;
      seconds = ttl.inSeconds;
    } else if (ttl is int) {
      seconds = ttl;
      ttlDuration = Duration(seconds: seconds);
    } else {
      seconds = 0;
      ttlDuration = null;
    }
    await store.put(_prefixed(key), result, seconds);
    _publishWrite(key, ttlDuration);
    return result;
  }

  /// Gets an item from the cache, or executes the given [callback] and stores
  /// the result forever.
  ///
  /// - Parameters:
  ///   - key: The key of the item to retrieve.
  ///   - callback: The function to execute if the item is not found.
  /// - Returns: The cached item or the result of the [callback].
  @override
  Future<dynamic> sear(String key, Function callback) async {
    return rememberForever(key, callback);
  }

  /// Gets an item from the cache, or executes the given [callback] and stores
  /// the result forever.
  ///
  /// - Parameters:
  ///   - key: The key of the item to retrieve.
  ///   - callback: The function to execute if the item is not found.
  /// - Returns: The cached item or the result of the [callback].
  @override
  Future<dynamic> rememberForever(String key, Function callback) async {
    final existing = await store.get(_prefixed(key));
    if (existing != null) {
      _publishHit(key);
      return existing;
    }
    _publishMiss(key);
    final result = await Function.apply(callback, const <dynamic>[]);
    await store.put(_prefixed(key), result, 0);
    _publishWrite(key, null);
    return result;
  }

  /// Removes an item from the cache.
  ///
  /// - Parameters:
  ///   - key: The key of the item to remove.
  /// - Returns: A boolean indicating whether the operation was successful.
  @override
  Future<bool> forget(String key) async {
    final result = await store.forget(_prefixed(key));
    if (result) {
      _publishForget(key);
    }
    return result;
  }

  /// Gets the cache store implementation.
  ///
  /// - Returns: The underlying cache store.
  @override
  Store getStore() {
    return store;
  }
}
