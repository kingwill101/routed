import 'package:routed/src/cache/lock.dart';

import 'redis_store.dart';

class RedisLock extends CacheLock {
  RedisLock(this._store, String name, int seconds, [String? owner])
    : super(name, seconds, owner);

  final RedisStore _store;

  @override
  Future<bool> acquire() {
    return _store.acquireLock(name, ownerId, seconds);
  }

  @override
  Future<String?> getCurrentOwner() {
    return _store.lockOwner(name);
  }

  @override
  Future<bool> release() {
    return _store.releaseLock(name, ownerId);
  }

  @override
  void forceRelease() {
    _store.forceReleaseLock(name);
  }
}
