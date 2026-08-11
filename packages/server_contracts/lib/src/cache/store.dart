import 'dart:async';

abstract class Store {
  FutureOr<dynamic> get(String key);

  FutureOr<Map<String, dynamic>> many(List<String> keys);

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

  FutureOr<bool> putMany(Map<String, dynamic> values, int seconds);

  FutureOr<dynamic> increment(String key, [int value = 1]);

  FutureOr<dynamic> decrement(String key, [int value = 1]);

  FutureOr<bool> forever(String key, dynamic value);

  FutureOr<bool> forget(String key);

  FutureOr<bool> flush();

  String getPrefix();

  FutureOr<List<String>> getAllKeys();
}
