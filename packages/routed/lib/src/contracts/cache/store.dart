import 'dart:async';

abstract class Store {
  /// Retrieves an item from the cache by [key].
  ///
  /// Returns the cached value or `null` if the key does not exist.
  FutureOr<dynamic> get(String key);

  /// Retrieves multiple items from the cache by their [keys].
  ///
  /// Items not found in the cache will have a `null` value.
  FutureOr<Map<String, dynamic>> many(List<String> keys);

  /// Stores an item in the cache for a given number of [seconds].
  ///
  /// Returns `true` if the item was successfully stored.
  FutureOr<bool> put(String key, dynamic value, int seconds);

  /// Stores multiple items in the cache for a given number of [seconds].
  ///
  /// Returns `true` if the items were successfully stored.
  FutureOr<bool> putMany(Map<String, dynamic> values, int seconds);

  /// Increments the value of an item in the cache by [value].
  ///
  /// Returns the new value.
  FutureOr<dynamic> increment(String key, [dynamic value = 1]);

  /// Decrements the value of an item in the cache by [value].
  ///
  /// Returns the new value.
  FutureOr<dynamic> decrement(String key, [dynamic value = 1]);

  /// Stores an item in the cache indefinitely.
  ///
  /// Returns `true` if the item was successfully stored.
  FutureOr<bool> forever(String key, dynamic value);

  /// Removes an item from the cache by [key].
  ///
  /// Returns `true` if the item was successfully removed.
  FutureOr<bool> forget(String key);

  /// Removes all items from the cache.
  ///
  /// Returns `true` if all items were successfully removed.
  FutureOr<bool> flush();

  /// Gets the cache key prefix.
  ///
  /// Returns the prefix used for cache keys.
  String getPrefix();

  /// Get all keys in the store.
  ///
  /// This method returns a list of all keys in the store.
  FutureOr<List<String>> getAllKeys();
}
