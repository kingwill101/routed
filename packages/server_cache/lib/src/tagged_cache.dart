import 'package:server_cache/src/tag_set.dart';
import 'package:server_contracts/server_contracts.dart';

/// A cache repository that supports tagging.
///
/// Every key is scoped by the current tag namespace, so entries written under
/// one set of tag IDs are never visible to a different set, and resetting or
/// flushing a tag (which changes the namespace) invalidates previously cached
/// values for that tag.
class TaggedCache implements Repository {
  /// Creates a new instance of [TaggedCache] with the given [store] and [tags].
  TaggedCache(this.store, this.tags);

  /// The underlying store used for caching.
  final Store store;

  /// The set of tags associated with the cache.
  final TagSet tags;

  /// Scopes [key] by the current tag namespace.
  ///
  /// An empty namespace (no tags configured) leaves the key untouched.
  Future<String> _namespaced(String key) async {
    final namespace = await tags.getNamespace();
    if (namespace.isEmpty) {
      return key;
    }
    return '$key|$namespace';
  }

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
    final keyString = key is String ? key : key.toString();
    final namespaced = await _namespaced(keyString);
    final value = await store.get(namespaced);
    await store.forget(namespaced);
    return value ?? defaultValue;
  }

  @override
  Future<dynamic> get(String key) async {
    return await store.get(await _namespaced(key));
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
    return await store.put(await _namespaced(key), value, ttl?.inSeconds ?? 0);
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
    // Delegates to the store's atomic store-only-if-absent operation so
    // concurrent callers cannot both report success for the same key.
    return await store.add(await _namespaced(key), value, ttl?.inSeconds ?? 0);
  }

  /// Increments the value of an item in the cache.
  ///
  /// - [key]: The key of the item to increment.
  /// - [value]: The amount by which to increment the item.
  ///
  /// Returns the new value of the item.
  @override
  Future<dynamic> increment(String key, [dynamic value = 1]) async {
    final namespaced = await _namespaced(key);
    final currentValue = await store.get(namespaced) ?? 0;
    final incrementValue = value is int ? value : 1;
    final newValue = (currentValue as num) + incrementValue;
    await store.put(namespaced, newValue, 0);
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
    final namespaced = await _namespaced(key);
    final currentValue = await store.get(namespaced) ?? 0;
    final decrementValue = value is int ? value : 1;
    final newValue = (currentValue as num) - decrementValue;
    await store.put(namespaced, newValue, 0);
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
    return await store.put(await _namespaced(key), value, 0);
  }

  /// Gets an item from the cache, or executes the given [callback] and stores
  /// the result.
  ///
  /// - [key]: The key of the item to retrieve.
  /// - [ttl]: The time-to-live duration for the cache item.
  /// - [callback]: The function to execute if the item is not found.
  ///
  /// Returns the cached item or the result of the [callback].
  @override
  Future<dynamic> remember(String key, dynamic ttl, Function callback) async {
    final namespaced = await _namespaced(key);
    final value = await store.get(namespaced);
    if (value != null) {
      return value;
    }
    final result = await Function.apply(callback, const <dynamic>[]);
    final seconds = ttl is Duration ? ttl.inSeconds : (ttl is int ? ttl : 0);
    await store.put(namespaced, result, seconds);
    return result;
  }

  /// Gets an item from the cache, or executes the given [callback] and stores
  /// the result forever.
  ///
  /// - [key]: The key of the item to retrieve.
  /// - [callback]: The function to execute if the item is not found.
  ///
  /// Returns the cached item or the result of the [callback].
  @override
  Future<dynamic> sear(String key, Function callback) async {
    return rememberForever(key, callback);
  }

  /// Gets an item from the cache, or executes the given [callback] and stores
  /// the result forever.
  ///
  /// - [key]: The key of the item to retrieve.
  /// - [callback]: The function to execute if the item is not found.
  ///
  /// Returns the cached item or the result of the [callback].
  @override
  Future<dynamic> rememberForever(String key, Function callback) async {
    final namespaced = await _namespaced(key);
    final value = await store.get(namespaced);
    if (value != null) {
      return value;
    }
    final result = await Function.apply(callback, const <dynamic>[]);
    await store.put(namespaced, result, 0);
    return result;
  }

  /// Removes an item from the cache.
  ///
  /// - [key]: The key of the item to remove.
  ///
  /// Returns `true` if the item was successfully removed.
  @override
  Future<bool> forget(String key) async {
    return await store.forget(await _namespaced(key));
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
