import 'package:routed/src/cache/tag_set.dart';
import 'package:routed/src/contracts/cache/repository.dart';
import 'package:routed/src/contracts/cache/store.dart';

/// A cache repository that supports tagging.
class TaggedCache implements Repository {
  /// The underlying store used for caching.
  final Store store;

  /// The set of tags associated with the cache.
  final TagSet tags;

  /// Creates a new instance of [TaggedCache] with the given [store] and [tags].
  TaggedCache(this.store, this.tags);

  /// Retrieves an item from the cache and deletes it.
  ///
  /// If the item is not found, returns the [defaultValue].
  ///
  /// - [key]: The key of the item to retrieve.
  /// - [defaultValue]: The value to return if the item is not found.
  ///
  /// Returns the cached item or the [defaultValue] if the item is not found.
  @override
  Future<dynamic> pull(dynamic key, [dynamic defaultValue]) async {
    final String keyString = key is String ? key : key.toString();
    final value = await store.get(keyString);
    await store.forget(keyString);
    return value ?? defaultValue;
  }

  @override
  Future<dynamic> get(String key) async {
    return await store.get(key);
  }

  /// Stores an item in the cache.
  ///
  /// - [key]: The key under which to store the item.
  /// - [value]: The value to store.
  /// - [ttl]: The time-to-live duration for the cache item.
  ///
  /// Returns `true` if the item was successfully stored.
  @override
  Future<bool> put(String key, dynamic value, [Duration? ttl]) async {
    return await store.put(key, value, ttl?.inSeconds ?? 0);
  }

  /// Stores an item in the cache if the key does not exist.
  ///
  /// - [key]: The key under which to store the item.
  /// - [value]: The value to store.
  /// - [ttl]: The time-to-live duration for the cache item.
  ///
  /// Returns `true` if the item was successfully stored.
  @override
  Future<bool> add(String key, dynamic value, [Duration? ttl]) async {
    if (await store.get(key) == null) {
      return await store.put(key, value, ttl?.inSeconds ?? 0);
    }
    return false;
  }

  /// Increments the value of an item in the cache.
  ///
  /// - [key]: The key of the item to increment.
  /// - [value]: The amount by which to increment the item.
  ///
  /// Returns the new value of the item.
  @override
  Future<dynamic> increment(String key, [dynamic value = 1]) async {
    final currentValue = await store.get(key) ?? 0;
    final int incrementValue = value is int ? value : 1;
    final newValue = currentValue + incrementValue;
    await store.put(key, newValue, 0);
    return newValue;
  }

  /// Decrements the value of an item in the cache.
  ///
  /// - [key]: The key of the item to decrement.
  /// - [value]: The amount by which to decrement the item.
  ///
  /// Returns the new value of the item.
  @override
  Future<dynamic> decrement(String key, [dynamic value = 1]) async {
    final currentValue = await store.get(key) ?? 0;
    final int decrementValue = value is int ? value : 1;
    final newValue = currentValue - decrementValue;
    await store.put(key, newValue, 0);
    return newValue;
  }

  /// Stores an item in the cache indefinitely.
  ///
  /// - [key]: The key under which to store the item.
  /// - [value]: The value to store.
  ///
  /// Returns `true` if the item was successfully stored.
  @override
  Future<bool> forever(String key, dynamic value) async {
    return await store.put(key, value, 0);
  }

  /// Gets an item from the cache, or executes the given [callback] and stores the result.
  ///
  /// - [key]: The key of the item to retrieve.
  /// - [ttl]: The time-to-live duration for the cache item.
  /// - [callback]: The function to execute if the item is not found.
  ///
  /// Returns the cached item or the result of the [callback].
  @override
  Future<dynamic> remember(String key, dynamic ttl, Function callback) async {
    final value = await store.get(key);
    if (value != null) {
      return value;
    }
    final result = await callback();
    final int seconds = ttl is Duration
        ? ttl.inSeconds
        : (ttl is int ? ttl : 0);
    await store.put(key, result, seconds);
    return result;
  }

  /// Gets an item from the cache, or executes the given [callback] and stores the result forever.
  ///
  /// - [key]: The key of the item to retrieve.
  /// - [callback]: The function to execute if the item is not found.
  ///
  /// Returns the cached item or the result of the [callback].
  @override
  Future<dynamic> sear(String key, Function callback) async {
    return await rememberForever(key, callback);
  }

  /// Gets an item from the cache, or executes the given [callback] and stores the result forever.
  ///
  /// - [key]: The key of the item to retrieve.
  /// - [callback]: The function to execute if the item is not found.
  ///
  /// Returns the cached item or the result of the [callback].
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
  /// - [key]: The key of the item to remove.
  ///
  /// Returns `true` if the item was successfully removed.
  @override
  Future<bool> forget(String key) async {
    return await store.forget(key);
  }

  /// Gets the cache store implementation.
  ///
  /// Returns the underlying [Store] instance.
  @override
  Store getStore() {
    return store;
  }

  /// Gets the set of tags associated with the cache.
  ///
  /// Returns the [TagSet] instance.
  TagSet getTags() {
    return tags;
  }
}
