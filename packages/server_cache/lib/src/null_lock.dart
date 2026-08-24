import 'package:server_cache/src/lock.dart';

/// A no-op lock for disabled or non-persistent caching.
///
/// Every acquisition succeeds and the state is held only by this lock object.
/// It provides the lock API without mutual exclusion, so it must not be used
/// when concurrent callers need protection.
class NullLock extends CacheLock {
  /// Creates a lock that always reports successful acquisition.
  NullLock(super.name, super.seconds, [super.owner]);

  bool _acquired = false;

  /// Marks this lock as acquired.
  @override
  Future<bool> acquire() async {
    _acquired = true;
    return true;
  }

  /// Marks this lock as released.
  @override
  Future<bool> release() async {
    _acquired = false;
    return true;
  }

  /// Returns this lock's owner while its local state is acquired.
  @override
  Future<String?> getCurrentOwner() async {
    return _acquired ? ownerId : null;
  }

  /// Clears the local acquisition state without checking ownership.
  @override
  void forceRelease() {
    _acquired = false;
  }
}
