import 'dart:async';

/// Defines low-level key-value storage operations for a cache backend.
///
/// Keys are backend-defined strings and values are dynamic so that adapters
/// can choose their serialization format. A positive TTL in seconds expires
/// an entry; zero or a negative value requests no expiration.
///
/// ```dart
/// final stored = await store.add('invite:42', 'single-use', 300);
/// if (stored) {
///   // Only the caller that inserted the key should send the invite.
/// }
/// ```
abstract class Store {
  /// Returns the value for [key], or `null` when it is absent or expired.
  ///
  /// A stored null value is therefore indistinguishable from a miss through
  /// this method.
  FutureOr<dynamic> get(String key);

  /// Returns the values associated with [keys].
  ///
  /// Implementations may omit missing keys or include them with a null value;
  /// callers should treat null as a miss. The returned map uses the original
  /// cache keys, not backend-specific storage paths.
  FutureOr<Map<String, dynamic>> many(List<String> keys);

  /// Stores [value] under [key] for [seconds].
  ///
  /// A positive value is a TTL in seconds. Zero or a negative value requests
  /// that the entry not expire. Returns whether the backend accepted the
  /// write.
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

  /// Stores all [values] with the same TTL of [seconds].
  ///
  /// This operation is not required to be transactional. A `true` result
  /// indicates that the backend accepted the operation; it does not promise
  /// that a later failure cannot leave a partial write.
  FutureOr<bool> putMany(Map<String, dynamic> values, int seconds);

  /// Adds [value] to the numeric value stored at [key].
  ///
  /// The default increment is `1`. Implementations commonly treat a missing
  /// key as zero and return the new numeric value.
  FutureOr<dynamic> increment(String key, [int value = 1]);

  /// Subtracts [value] from the numeric value stored at [key].
  ///
  /// The default decrement is `1`. Implementations commonly treat a missing
  /// key as zero and return the new numeric value.
  FutureOr<dynamic> decrement(String key, [int value = 1]);

  /// Stores [value] without an expiration.
  FutureOr<bool> forever(String key, dynamic value);

  /// Removes [key] from the store.
  ///
  /// The returned boolean is backend-defined for an already-absent key.
  FutureOr<bool> forget(String key);

  /// Removes every entry from the store.
  ///
  /// This is destructive and may affect all users of the backend or
  /// namespace. Callers should not use it for routine key invalidation.
  FutureOr<bool> flush();

  /// Returns the prefix applied to keys by this store.
  ///
  /// The prefix may be empty. It describes the backend namespace and should
  /// not be assumed to be part of keys returned by [many] or [getAllKeys].
  String getPrefix();

  /// Returns the unexpired keys currently known to the store.
  ///
  /// Key enumeration may be expensive, incomplete, or unsupported for a
  /// backend. Implementations that cannot enumerate keys may return an empty
  /// list. Do not use this method as a substitute for an index or as a
  /// consistent snapshot during concurrent writes.
  FutureOr<List<String>> getAllKeys();
}
