import 'dart:async';

/// Low-level key-value cache store contract.
abstract class Store {
  /// Returns the value for [key], or `null` when absent.
  FutureOr<dynamic> get(String key);

  /// Returns values for all [keys] that are present.
  FutureOr<Map<String, dynamic>> many(List<String> keys);

  /// Stores [value] under [key] for [seconds].
  FutureOr<bool> put(String key, dynamic value, int seconds);

  /// Stores an item in the cache only if [key] is absent (or expired).
  ///
  /// Unlike [put], this never replaces an existing, unexpired entry, so
  /// concurrent callers cannot clobber each other's values. Stores should
  /// implement this atomically (e.g. exclusive file creation, `SET NX`).
  ///
  /// Returns `true` if the item was stored, `false` if [key] already holds
  /// an unexpired value.
  FutureOr<bool> add(String key, dynamic value, int seconds);

  /// Stores all [values] for [seconds].
  FutureOr<bool> putMany(Map<String, dynamic> values, int seconds);

  /// Increments [key] by [value].
  FutureOr<dynamic> increment(String key, [int value = 1]);

  /// Decrements [key] by [value].
  FutureOr<dynamic> decrement(String key, [int value = 1]);

  /// Stores [value] without an expiration.
  FutureOr<bool> forever(String key, dynamic value);

  /// Removes [key].
  FutureOr<bool> forget(String key);

  /// Removes every entry from the store.
  FutureOr<bool> flush();

  /// Prefix applied to keys by this store.
  String getPrefix();

  /// Returns all keys currently known to the store.
  FutureOr<List<String>> getAllKeys();
}
