import 'dart:async';

import 'store.dart';

abstract class Repository {
  /// Retrieves an item from the cache and deletes it.
  ///
  /// Returns the cached item or the [defaultValue] if the item is not found.
  FutureOr<dynamic> pull(dynamic key, [dynamic defaultValue]);

  /// Retrieves an item from the cache without mutating it.
  FutureOr<dynamic> get(String key);

  /// Stores an item in the cache.
  ///
  /// The [ttl] parameter specifies the time-to-live duration.
  FutureOr<bool> put(String key, dynamic value, [Duration? ttl]);

  /// Stores an item in the cache if the key does not exist.
  ///
  /// The [ttl] parameter specifies the time-to-live duration.
  FutureOr<bool> add(String key, dynamic value, [Duration? ttl]);

  /// Increments the value of an item in the cache.
  ///
  /// The [value] parameter specifies the increment amount.
  FutureOr<dynamic> increment(String key, [dynamic value = 1]);

  /// Decrements the value of an item in the cache.
  ///
  /// The [value] parameter specifies the decrement amount.
  FutureOr<dynamic> decrement(String key, [dynamic value = 1]);

  /// Stores an item in the cache indefinitely.
  FutureOr<bool> forever(String key, dynamic value);

  /// Gets an item from the cache, or executes the given [callback] and stores the result.
  ///
  /// The [ttl] parameter specifies the time-to-live duration.
  FutureOr<dynamic> remember(String key, dynamic ttl, Function callback);

  /// Gets an item from the cache, or executes the given [callback] and stores the result forever.
  FutureOr<dynamic> sear(String key, Function callback);

  /// Gets an item from the cache, or executes the given [callback] and stores the result forever.
  FutureOr<dynamic> rememberForever(String key, Function callback);

  /// Removes an item from the cache.
  FutureOr<bool> forget(String key);

  /// Gets the cache store implementation.
  Store getStore();
}
