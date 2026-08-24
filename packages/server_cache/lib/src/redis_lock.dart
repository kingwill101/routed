import 'package:server_cache/src/lock.dart';
import 'package:server_cache/src/redis_store.dart';

/// Redis-backed implementation of [CacheLock].
///
/// Acquisition and owner-checked release are delegated to Redis commands, so
/// this lock can coordinate separate processes that share the same Redis
/// database.
class RedisLock extends CacheLock {
  /// Creates a lock backed by a [RedisStore].
  RedisLock(this._store, String name, int seconds, [String? owner])
    : super(name, seconds, owner);

  final RedisStore _store;

  /// Attempts to acquire the Redis lock with this instance's owner ID.
  @override
  Future<bool> acquire() {
    return _store.acquireLock(name, ownerId, seconds);
  }

  /// Returns the owner currently recorded in Redis.
  @override
  Future<String?> getCurrentOwner() {
    return _store.lockOwner(name);
  }

  /// Releases the lock only when Redis records this instance as the owner.
  @override
  Future<bool> release() {
    return _store.releaseLock(name, ownerId);
  }

  /// Removes the Redis lock key without checking its owner.
  @override
  void forceRelease() {
    _store.forceReleaseLock(name);
  }
}
