import 'package:routed/src/contracts/cache/repository.dart';
import 'package:routed/src/contracts/cache/store.dart';

/// Implementation of the [Repository] interface.
/// This class provides methods to interact with the cache store.
class RepositoryImpl implements Repository {
  /// The underlying cache store.
  final Store store;

  /// Constructs a [RepositoryImpl] with the given [store].
  RepositoryImpl(this.store);

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
    final value = await store.get(key);
    await store.forget(key);
    return value ?? defaultValue;
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
    return await store.put(key, value, ttl?.inSeconds ?? 0);
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
    if (await store.get(key) == null) {
      return await store.put(key, value, ttl?.inSeconds ?? 0);
    }
    return false;
  }

  /// Increments the value of an item in the cache.
  ///
  /// - Parameters:
  ///   - key: The key of the item to increment.
  ///   - value: The increment amount (default is 1).
  /// - Returns: The new value after incrementing.
  @override
  Future<dynamic> increment(String key, [dynamic value = 1]) async {
    return await store.increment(key, value);
  }

  /// Decrements the value of an item in the cache.
  ///
  /// - Parameters:
  ///   - key: The key of the item to decrement.
  ///   - value: The decrement amount (default is 1).
  /// - Returns: The new value after decrementing.
  @override
  Future<dynamic> decrement(String key, [dynamic value = 1]) async {
    return await store.decrement(key, value);
  }

  /// Stores an item in the cache indefinitely.
  ///
  /// - Parameters:
  ///   - key: The key of the item to store.
  ///   - value: The value of the item to store.
  /// - Returns: A boolean indicating whether the operation was successful.
  @override
  Future<bool> forever(String key, dynamic value) async {
    return await store.forever(key, value);
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
    final value = await store.get(key);
    if (value != null) {
      return value;
    }
    final result = await callback();
    int seconds = ttl is Duration ? ttl.inSeconds : ttl;
    await store.put(key, result, seconds);
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
    final value = await store.get(key);
    if (value != null) {
      return value;
    }
    final result = await callback();
    await store.put(key, result, 0);
    return result;
  }

  /// Removes an item from the cache.
  ///
  /// - Parameters:
  ///   - key: The key of the item to remove.
  /// - Returns: A boolean indicating whether the operation was successful.
  @override
  Future<bool> forget(String key) async {
    return await store.forget(key);
  }

  /// Gets the cache store implementation.
  ///
  /// - Returns: The underlying cache store.
  @override
  Store getStore() {
    return store;
  }
}
