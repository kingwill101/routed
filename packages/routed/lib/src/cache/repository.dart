import 'package:routed/src/contracts/cache/repository.dart';
import 'package:routed/src/contracts/cache/store.dart';
import 'package:routed/src/events/cache/cache_events.dart';
import 'package:routed/src/events/event_manager.dart';

/// Implementation of the [Repository] interface.
/// This class provides methods to interact with the cache store.
class RepositoryImpl implements Repository {
  final Store store;
  final String storeName;
  EventManager? _eventManager;
  String _prefix;

  RepositoryImpl(
    this.store,
    this.storeName,
    this._prefix, [
    EventManager? eventManager,
  ]) : _eventManager = eventManager;

  void attachEventManager(EventManager? eventManager) {
    _eventManager = eventManager;
  }

  void updatePrefix(String prefix) {
    _prefix = prefix;
  }

  void _publish(CacheEvent event) {
    _eventManager?.publish(event);
  }

  String _prefixed(String key) => _prefix.isEmpty ? key : '$_prefix$key';

  void _publishHit(String key) {
    _publish(CacheHitEvent(store: storeName, key: key));
  }

  void _publishMiss(String key) {
    _publish(CacheMissEvent(store: storeName, key: key));
  }

  void _publishWrite(String key, Duration? ttl) {
    _publish(CacheWriteEvent(store: storeName, key: key, ttl: ttl));
  }

  void _publishForget(String key) {
    _publish(CacheForgetEvent(store: storeName, key: key));
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
    final String keyString = key is String ? key : key.toString();
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
    final success = await store.put(_prefixed(key), value, ttl?.inSeconds ?? 0);
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
    final int incrementValue = value is int ? value : 1;
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
    final int decrementValue = value is int ? value : 1;
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

  /// Gets an item from the cache, or executes the given [callback] and stores the result.
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
    final result = await callback();
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

  /// Gets an item from the cache, or executes the given [callback] and stores the result forever.
  ///
  /// - Parameters:
  ///   - key: The key of the item to retrieve.
  ///   - callback: The function to execute if the item is not found.
  /// - Returns: The cached item or the result of the [callback].
  @override
  Future<dynamic> sear(String key, Function callback) async {
    return await rememberForever(key, callback);
  }

  /// Gets an item from the cache, or executes the given [callback] and stores the result forever.
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
    final result = await callback();
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
