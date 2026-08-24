import 'dart:async';

import 'package:server_contracts/src/cache/store.dart';

/// Provides a high-level cache API over a low-level [Store].
///
/// Repositories commonly add key prefixes, instrumentation, or convenience
/// operations around a store. Cache values are dynamic by design; callers
/// should validate or cast values at the boundary where they read them.
abstract class Repository {
  /// Returns the value for [key] and removes it from the cache.
  ///
  /// Returns [defaultValue] when [key] is absent or expired. The removal is
  /// performed after a successful read, so this operation is useful for
  /// one-time values such as queue messages or login tokens.
  FutureOr<dynamic> pull(dynamic key, [dynamic defaultValue]);

  /// Returns the value for [key], or `null` when it is absent or expired.
  ///
  /// A `null` result cannot distinguish a miss from a backend that permits a
  /// stored null value; use a non-null sentinel when that distinction matters.
  FutureOr<dynamic> get(String key);

  /// Stores [value] under [key] for the optional [ttl].
  ///
  /// A missing or non-positive TTL requests storage without expiration. The
  /// returned value indicates whether the backend accepted the write.
  FutureOr<bool> put(String key, dynamic value, [Duration? ttl]);

  /// Stores [value] only when [key] is absent or expired.
  ///
  /// Returns `true` when this call wins the insertion and `false` when an
  /// unexpired value already exists or another caller wins an atomic race.
  FutureOr<bool> add(String key, dynamic value, [Duration? ttl]);

  /// Adds [value] to the numeric value stored at [key].
  ///
  /// The default increment is `1`. Implementations commonly treat a missing
  /// key as zero and return the new value, but the numeric representation is
  /// backend-defined.
  FutureOr<dynamic> increment(String key, [dynamic value = 1]);

  /// Subtracts [value] from the numeric value stored at [key].
  ///
  /// The default decrement is `1`. Implementations commonly treat a missing
  /// key as zero and return the new value.
  FutureOr<dynamic> decrement(String key, [dynamic value = 1]);

  /// Stores [value] without an expiration.
  FutureOr<bool> forever(String key, dynamic value);

  /// Returns the existing value for [key], or computes and stores it.
  ///
  /// [ttl] may be a [Duration] or an integer number of seconds. The zero-arg
  /// [callback] runs only on a miss, and its result is returned and cached.
  /// Unless an implementation documents stronger coordination, concurrent
  /// misses may evaluate [callback] more than once.
  FutureOr<dynamic> remember(String key, dynamic ttl, Function callback);

  /// Computes and stores [key] forever when it is missing.
  ///
  /// This is the historical shorthand for [rememberForever].
  FutureOr<dynamic> sear(String key, Function callback);

  /// Returns the existing value for [key], or stores the callback result
  /// without an expiration.
  ///
  /// The zero-arg [callback] runs only on a miss. Unless an implementation
  /// documents stronger coordination, concurrent misses may evaluate it more
  /// than once.
  FutureOr<dynamic> rememberForever(String key, Function callback);

  /// Removes [key] from the repository.
  ///
  /// Returns whether the backend reports that an entry was removed. Backends
  /// may differ in whether removing an already-absent key is considered a
  /// successful operation.
  FutureOr<bool> forget(String key);

  /// Returns the underlying low-level store.
  ///
  /// Use this when an operation is specific to a backend contract, such as
  /// [Store.many] or [Store.flush].
  Store getStore();
}
