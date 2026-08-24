import 'package:server_cache/src/null_lock.dart';
import 'package:server_cache/src/taggable_store.dart';
import 'package:server_contracts/server_contracts.dart';

/// No-op store for disabled or intentionally non-persistent caching.
///
/// Writes report success but are discarded, reads report misses, and locks do
/// not provide mutual exclusion. This is useful for optional caching paths,
/// but it must not be used when data durability or concurrency protection is
/// required.
class NullStore extends TaggableStore implements Store, LockProvider {
  /// Returns an empty key list because this store retains no entries.
  @override
  Future<List<String>> getAllKeys() async => const <String>[];

  /// Always reports a cache miss.
  @override
  Future<dynamic> get(String key) async => null;

  /// Discards [value] and reports a successful write.
  @override
  Future<bool> put(String key, dynamic value, int seconds) async => true;

  /// Discards [value] and reports a successful conditional write.
  @override
  Future<bool> add(String key, dynamic value, int seconds) async => true;

  /// Discards all [values] and reports success.
  @override
  Future<bool> putMany(Map<String, dynamic> values, int seconds) async => true;

  /// Returns the requested increment because no value is persisted.
  @override
  Future<dynamic> increment(String key, [dynamic value = 1]) async =>
      value is num ? value : 1;

  /// Returns the negated requested decrement because no value is persisted.
  @override
  Future<dynamic> decrement(String key, [dynamic value = 1]) async =>
      value is num ? -value : -1;

  /// Discards [value] and reports a successful non-expiring write.
  @override
  Future<bool> forever(String key, dynamic value) async => true;

  /// Reports a successful removal even though no entry is stored.
  @override
  Future<bool> forget(String key) async => true;

  /// Reports a successful flush without changing state.
  @override
  Future<bool> flush() async => true;

  /// Returns the empty key prefix.
  @override
  String getPrefix() => '';

  /// Creates a no-op lock handle for [name].
  @override
  Future<Lock> lock(String name, [int seconds = 0, String? owner]) async =>
      NullLock(name, seconds, owner);

  /// Restores an acquired no-op lock handle for [name] and [owner].
  @override
  Future<Lock> restoreLock(String name, String owner) async {
    final lock = NullLock(name, 0, owner);
    await lock.acquire();
    return lock;
  }

  /// Returns an empty result for every requested key.
  @override
  Future<Map<String, dynamic>> many(List<String> keys) async =>
      <String, dynamic>{};
}
