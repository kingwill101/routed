import 'dart:async';

import 'store.dart';

/// High-level cache repository contract.
abstract class Repository {
  /// Returns [key] and removes it, or returns [defaultValue] when absent.
  FutureOr<dynamic> pull(dynamic key, [dynamic defaultValue]);

  /// Returns the value for [key], or `null` when absent.
  FutureOr<dynamic> get(String key);

  /// Stores [value] under [key] for the optional [ttl].
  FutureOr<bool> put(String key, dynamic value, [Duration? ttl]);

  /// Stores [value] only when [key] is absent or expired.
  FutureOr<bool> add(String key, dynamic value, [Duration? ttl]);

  /// Increments [key] by [value].
  FutureOr<dynamic> increment(String key, [dynamic value = 1]);

  /// Decrements [key] by [value].
  FutureOr<dynamic> decrement(String key, [dynamic value = 1]);

  /// Stores [value] without an expiration.
  FutureOr<bool> forever(String key, dynamic value);

  /// Returns the existing value for [key], or computes and stores it with [callback].
  FutureOr<dynamic> remember(String key, dynamic ttl, Function callback);

  /// Computes and stores [key] when it is missing.
  FutureOr<dynamic> sear(String key, Function callback);

  /// Returns the existing value for [key], or stores the result of [callback] forever.
  FutureOr<dynamic> rememberForever(String key, Function callback);

  /// Removes [key] from the repository.
  FutureOr<bool> forget(String key);

  /// Returns the underlying low-level store.
  Store getStore();
}
